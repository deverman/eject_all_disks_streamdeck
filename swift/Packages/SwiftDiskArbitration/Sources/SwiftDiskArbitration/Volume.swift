//
//  Volume.swift
//  SwiftDiskArbitration
//
//  Represents an external volume with its associated DADisk reference.
//

import DiskArbitration
import Foundation

/// Information about a mounted volume.
public struct VolumeInfo: Sendable, Codable, Hashable {
  /// Display name of the volume (e.g., "My USB Drive")
  public let name: String

  /// Full path to the mount point (e.g., "/Volumes/My USB Drive")
  public let path: String

  /// BSD device name (e.g., "disk2s1")
  public let bsdName: String?

  /// Whether the system reports this volume as ejectable
  public let isEjectable: Bool

  /// Whether the system reports this volume as removable media
  public let isRemovable: Bool

  /// Whether this is an internal drive
  public let isInternal: Bool

  /// Whether this is a disk image (.dmg)
  public let isDiskImage: Bool

  public init(
    name: String,
    path: String,
    bsdName: String? = nil,
    isEjectable: Bool = false,
    isRemovable: Bool = false,
    isInternal: Bool = true,
    isDiskImage: Bool = false
  ) {
    self.name = name
    self.path = path
    self.bsdName = bsdName
    self.isEjectable = isEjectable
    self.isRemovable = isRemovable
    self.isInternal = isInternal
    self.isDiskImage = isDiskImage
  }
}

/// A volume with its associated DADisk reference for direct DiskArbitration operations.
/// This type caches the DADisk reference to avoid recreation overhead during ejection.
///
/// Thread Safety: This type is marked @unchecked Sendable because:
/// - VolumeInfo is immutable and Sendable
/// - DADisk (CFType) is thread-safe for read operations after creation
/// - The disk reference is only used for unmount/eject operations which are thread-safe
public final class Volume: @unchecked Sendable {
  /// Information about this volume
  public let info: VolumeInfo

  /// The cached DADisk reference for this volume
  /// This avoids the overhead of calling DADiskCreateFromVolumePath during ejection
  internal let disk: DADisk

  /// The whole-disk reference (for multi-partition devices)
  /// Cached lazily when needed for ejection
  internal private(set) var wholeDisk: DADisk?

  /// URL for the volume mount point
  public var url: URL {
    URL(fileURLWithPath: info.path)
  }

  /// Creates a Volume from volume info and a pre-created DADisk reference
  /// - Parameters:
  ///   - info: The volume information
  ///   - disk: The DADisk reference (will be retained)
  internal init(info: VolumeInfo, disk: DADisk) {
    self.info = info
    self.disk = disk
    // Pre-cache the whole disk reference
    self.wholeDisk = DADiskCopyWholeDisk(disk)
  }

  deinit {
    // DADisk is a CFType, Swift handles release via ARC
    // wholeDisk is also managed by ARC
  }

  /// Returns the BSD name of the whole disk (physical device).
  /// For example, if this volume is "disk2s1", returns "disk2"
  /// Returns nil if the whole disk reference is not available
  internal var wholeDiskBSDName: String? {
    guard let wholeDisk = wholeDisk,
      let bsdName = DADiskGetBSDName(wholeDisk)
    else {
      return nil
    }
    return String(cString: bsdName)
  }
}

// MARK: - Volume Discovery

extension Volume {
  /// System volume patterns to exclude from ejection
  private static let excludedVolumePatterns: Set<String> = [
    "Macintosh HD",
    "Macintosh HD - Data",
    "Recovery",
    "Preboot",
    "VM",
    "Update",
  ]

  /// Enumerates all ejectable external volumes.
  ///
  /// This method scans /Volumes and returns volumes that are:
  /// - External (not internal drives)
  /// - Ejectable or removable
  /// - Not system volumes
  ///
  /// Each returned Volume includes a cached DADisk reference for fast ejection.
  ///
  /// - Parameter session: The DiskArbitration session to use
  /// - Returns: Array of ejectable volumes with cached disk references
  public static func enumerateEjectableVolumes(session: DASession) -> [Volume] {
    let fileManager = FileManager.default
    let volumesPath = "/Volumes"

    guard let contents = try? fileManager.contentsOfDirectory(atPath: volumesPath) else {
      return []
    }

    var volumes: [Volume] = []

    for name in contents {
      // Skip hidden files
      guard !name.hasPrefix(".") else { continue }

      // Skip Apple system volumes
      guard !name.hasPrefix("com.apple.") else { continue }

      // Skip Time Machine backups
      guard !name.hasPrefix("Backups of ") else { continue }

      // Skip known system volumes
      guard !excludedVolumePatterns.contains(name) else { continue }

      let path = "\(volumesPath)/\(name)"
      let url = URL(fileURLWithPath: path)

      // Verify it's a directory (mount point)
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        continue
      }

      // Get volume properties from the filesystem
      var isEjectable = false
      var isRemovable = false
      var isInternal = true

      if let resourceValues = try? url.resourceValues(forKeys: [
        .volumeIsEjectableKey,
        .volumeIsRemovableKey,
        .volumeIsInternalKey,
      ]) {
        isEjectable = resourceValues.volumeIsEjectable ?? false
        isRemovable = resourceValues.volumeIsRemovable ?? false
        isInternal = resourceValues.volumeIsInternal ?? true
      }

      // Include if: ejectable OR removable OR external
      guard isEjectable || isRemovable || !isInternal else {
        continue
      }

      // Create DADisk reference from the volume path
      // This is cached for later use during ejection
      guard
        let disk = DADiskCreateFromVolumePath(
          kCFAllocatorDefault,
          session,
          url as CFURL
        )
      else {
        continue
      }

      // Get BSD name from the disk
      var bsdName: String? = nil
      if let bsdNameCStr = DADiskGetBSDName(disk) {
        bsdName = String(cString: bsdNameCStr)
      }

      // Check if it's a disk image
      let isDiskImage = checkIfDiskImage(disk: disk)

      let info = VolumeInfo(
        name: name,
        path: path,
        bsdName: bsdName,
        isEjectable: isEjectable,
        isRemovable: isRemovable,
        isInternal: isInternal,
        isDiskImage: isDiskImage
      )

      volumes.append(Volume(info: info, disk: disk))
    }

    return volumes
  }

  /// Checks if a disk is a disk image (.dmg)
  private static func checkIfDiskImage(disk: DADisk) -> Bool {
    guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
      return false
    }

    // Check the device model key for "Disk Image"
    if let model = description[kDADiskDescriptionDeviceModelKey as String] as? String {
      return model == "Disk Image"
    }

    return false
  }
}

// MARK: - CustomStringConvertible

extension Volume: CustomStringConvertible {
  public var description: String {
    var flags: [String] = []
    if info.isEjectable { flags.append("ejectable") }
    if info.isRemovable { flags.append("removable") }
    if !info.isInternal { flags.append("external") }
    if info.isDiskImage { flags.append("disk-image") }

    let flagsStr = flags.isEmpty ? "none" : flags.joined(separator: ", ")
    return "Volume(\"\(info.name)\", bsd: \(info.bsdName ?? "?"), flags: [\(flagsStr)])"
  }
}
