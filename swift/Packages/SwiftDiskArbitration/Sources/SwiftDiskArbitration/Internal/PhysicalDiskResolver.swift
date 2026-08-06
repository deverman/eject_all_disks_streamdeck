//
//  PhysicalDiskResolver.swift
//  SwiftDiskArbitration
//
//  Resolves a mounted volume through synthesized storage layers (notably APFS)
//  into the ordered whole-media stack Disk Arbitration must eject.
//

import DiskArbitration
import Foundation
import IOKit
import IOKit.storage

internal struct ResolvedDiskLayer: @unchecked Sendable {
  let disk: DADisk
  let bsdName: String
}

internal struct ResolvedDiskTopology: @unchecked Sendable {
  /// Whole-media layers ordered from the mounted filesystem outward to the
  /// physical device. APFS commonly resolves to `[disk7, disk6]`.
  let layers: [ResolvedDiskLayer]

  var unmountDisk: DADisk { layers[0].disk }
  var physicalDisk: DADisk { layers[layers.count - 1].disk }
  var physicalBSDName: String { layers[layers.count - 1].bsdName }
  var bsdNames: [String] { layers.map(\.bsdName) }

  init?(layers: [ResolvedDiskLayer]) {
    guard !layers.isEmpty else { return nil }
    self.layers = layers
  }
}

internal struct ResolvedDeviceEjectTopology: @unchecked Sendable {
  /// Whole disks that need a whole-disk unmount before any eject is submitted.
  let unmountLayers: [ResolvedDiskLayer]

  /// Unique whole-media layers in dependency order, with the physical disk last.
  let ejectLayers: [ResolvedDiskLayer]

  var physicalDisk: DADisk { ejectLayers[ejectLayers.count - 1].disk }
  var physicalBSDName: String { ejectLayers[ejectLayers.count - 1].bsdName }

  init?(topologies: [ResolvedDiskTopology]) {
    guard let physicalBSDName = topologies.first?.physicalBSDName else { return nil }
    guard topologies.allSatisfy({ $0.physicalBSDName == physicalBSDName }) else {
      return nil
    }

    var layerByBSDName: [String: ResolvedDiskLayer] = [:]
    var maximumDepthByBSDName: [String: Int] = [:]
    var unmountLayerByBSDName: [String: ResolvedDiskLayer] = [:]
    var unmountDepthByBSDName: [String: Int] = [:]

    for topology in topologies {
      let finalIndex = topology.layers.count - 1
      for (index, layer) in topology.layers.enumerated() {
        let depth = finalIndex - index
        layerByBSDName[layer.bsdName] = layer
        maximumDepthByBSDName[layer.bsdName] = max(
          maximumDepthByBSDName[layer.bsdName] ?? depth,
          depth
        )
      }

      let unmountLayer = topology.layers[0]
      unmountLayerByBSDName[unmountLayer.bsdName] = unmountLayer
      unmountDepthByBSDName[unmountLayer.bsdName] = max(
        unmountDepthByBSDName[unmountLayer.bsdName] ?? finalIndex,
        finalIndex
      )
    }

    let ejectNames = layerByBSDName.keys.sorted { lhs, rhs in
      let lhsDepth = maximumDepthByBSDName[lhs] ?? 0
      let rhsDepth = maximumDepthByBSDName[rhs] ?? 0
      if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
      return lhs < rhs
    }
    let unmountNames = unmountLayerByBSDName.keys.sorted { lhs, rhs in
      let lhsDepth = unmountDepthByBSDName[lhs] ?? 0
      let rhsDepth = unmountDepthByBSDName[rhs] ?? 0
      if lhsDepth != rhsDepth { return lhsDepth > rhsDepth }
      return lhs < rhs
    }

    guard
      let physicalName = ejectNames.last,
      physicalName == physicalBSDName
    else {
      return nil
    }

    unmountLayers = unmountNames.compactMap { unmountLayerByBSDName[$0] }
    ejectLayers = ejectNames.compactMap { layerByBSDName[$0] }
    guard !unmountLayers.isEmpty, !ejectLayers.isEmpty else { return nil }
  }
}

internal struct DiskEjectPlan: Sendable, Equatable {
  let unmountBSDNames: [String]
  let ejectBSDNames: [String]
  let physicalBSDName: String

  init?(unmountBSDNames: [String], ejectBSDNames: [String]) {
    guard
      !unmountBSDNames.isEmpty,
      let last = ejectBSDNames.last
    else { return nil }
    self.unmountBSDNames = unmountBSDNames
    self.ejectBSDNames = ejectBSDNames
    physicalBSDName = last
  }
}

internal enum PhysicalDiskResolver {
  private enum ParentResolution {
    case none
    case one(io_registry_entry_t)
    case ambiguousOrUnavailable
  }

  /// I/O Registry storage stacks are shallow. The bound prevents a malformed
  /// or cyclic provider graph from keeping an eject operation from completing.
  private static let maximumAncestorDepth = 128

  /// Returns every whole medium in the disk's I/O Service ancestry, ordered
  /// from the mounted filesystem outward to the physical device.
  ///
  /// `DADiskCopyWholeDisk` is intentionally insufficient here: Apple documents
  /// that a whole IOMedia can be either a physical disk or a virtual replica.
  /// For APFS, the synthesized whole disk (for example `disk7`) must be
  /// unmounted/ejected before its physical ancestor (for example `disk6`).
  ///
  /// Every IOKit object copied by this function is released exactly once.
  static func resolve(_ disk: DADisk, session: DASession) -> ResolvedDiskTopology? {
    var current = DADiskCopyIOMedia(disk)
    guard current != IO_OBJECT_NULL else { return nil }

    var layers: [ResolvedDiskLayer] = []

    for _ in 0..<maximumAncestorDepth {
      if unsafe IOObjectConformsTo(current, kIOMediaClass) != 0,
        let candidate = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, current),
        isWhole(candidate),
        let bsdName = DiskArbitrationUnsafeAdapter.bsdName(of: candidate)
      {
        layers.append(ResolvedDiskLayer(disk: candidate, bsdName: bsdName))
      }

      switch copyOnlyParent(of: current) {
      case .none:
        _ = IOObjectRelease(current)
        return ResolvedDiskTopology(layers: layers)
      case .one(let parent):
        _ = IOObjectRelease(current)
        current = parent
      case .ambiguousOrUnavailable:
        _ = IOObjectRelease(current)
        return nil
      }
    }

    // The depth bound was reached. Release the final retained entry and fail
    // closed instead of trusting a possibly incomplete ancestry traversal.
    _ = IOObjectRelease(current)
    return nil
  }

  private static func isWhole(_ disk: DADisk) -> Bool {
    guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
      return false
    }
    return description[kDADiskDescriptionMediaWholeKey as String] as? Bool == true
  }

  /// Returns a retained parent only when the service has exactly one parent.
  /// Multi-parent media (for example some RAID graphs) cannot be represented by
  /// this library's one-device eject workflow, so ambiguity fails closed.
  private static func copyOnlyParent(of entry: io_registry_entry_t) -> ParentResolution {
    var iterator = IO_OBJECT_NULL
    let result = unsafe IORegistryEntryGetParentIterator(
      entry,
      kIOServicePlane,
      &iterator
    )
    guard result == KERN_SUCCESS, iterator != IO_OBJECT_NULL else {
      return .ambiguousOrUnavailable
    }
    defer { _ = IOObjectRelease(iterator) }

    let first = IOIteratorNext(iterator)
    guard first != IO_OBJECT_NULL else { return .none }

    let second = IOIteratorNext(iterator)
    guard second == IO_OBJECT_NULL else {
      _ = IOObjectRelease(first)
      _ = IOObjectRelease(second)
      while true {
        let extra = IOIteratorNext(iterator)
        guard extra != IO_OBJECT_NULL else { break }
        _ = IOObjectRelease(extra)
      }
      return .ambiguousOrUnavailable
    }

    return .one(first)
  }
}
