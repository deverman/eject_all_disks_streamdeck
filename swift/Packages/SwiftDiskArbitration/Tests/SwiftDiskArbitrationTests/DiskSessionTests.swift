//
//  DiskSessionTests.swift
//  SwiftDiskArbitrationTests
//
//  Tests for DiskSession actor and operations
//

import DiskArbitration
import Foundation
import Testing

@testable import SwiftDiskArbitration

@Suite("DiskSession Tests")
struct DiskSessionTests {

  @Test("Shared session is available")
  func sharedSession() async throws {
    let session = try #require(DiskSession.shared)
    #expect(await session.ejectableVolumeCount() >= 0)
  }

  @Test("Multiple sessions can coexist")
  func multipleSessions() async throws {
    let session1 = try DiskSession()
    let session2 = try DiskSession()

    // Both should work independently
    let count1 = await session1.ejectableVolumeCount()
    let count2 = await session2.ejectableVolumeCount()

    #expect(count1 == count2, "Both sessions should see the same volumes")
  }

  @Test("Physical resolver ends at an idempotent outermost whole medium")
  func physicalResolverFindsOrderedWholeMedia() throws {
    let session = try #require(DASessionCreate(kCFAllocatorDefault))
    let rootDisk = try #require(DADiskCreateFromVolumePath(
      kCFAllocatorDefault,
      session,
      URL(fileURLWithPath: "/") as CFURL
    ))

    let firstResolution = try #require(PhysicalDiskResolver.resolve(
      rootDisk,
      session: session
    ))
    let secondResolution = try #require(PhysicalDiskResolver.resolve(
      firstResolution.physicalDisk,
      session: session
    ))

    #expect(!firstResolution.layers.isEmpty)
    #expect(firstResolution.physicalBSDName == secondResolution.physicalBSDName)
    #expect(secondResolution.bsdNames == [firstResolution.physicalBSDName])
  }

  @Test("APFS eject plan preserves inner-to-outer layer order")
  func apfsEjectPlanOrder() throws {
    let plan = try #require(DiskEjectPlan(
      unmountBSDNames: ["disk7"],
      ejectBSDNames: ["disk7", "disk6"]
    ))

    #expect(plan.unmountBSDNames == ["disk7"])
    #expect(plan.ejectBSDNames == ["disk7", "disk6"])
    #expect(plan.physicalBSDName == "disk6")
  }

  @Test("Device topology merges branches and keeps dependencies before physical media")
  func deviceTopologyMergesBranches() throws {
    let session = try #require(DASessionCreate(kCFAllocatorDefault))
    let rootDisk = try #require(DADiskCreateFromVolumePath(
      kCFAllocatorDefault,
      session,
      URL(fileURLWithPath: "/") as CFURL
    ))
    let layer: (String) -> ResolvedDiskLayer = {
      ResolvedDiskLayer(disk: rootDisk, bsdName: $0)
    }
    let deepBranch = try #require(ResolvedDiskTopology(
      layers: [layer("disk9"), layer("disk8"), layer("disk6")]
    ))
    let siblingBranch = try #require(ResolvedDiskTopology(
      layers: [layer("disk7"), layer("disk6")]
    ))
    let device = try #require(ResolvedDeviceEjectTopology(
      topologies: [siblingBranch, deepBranch]
    ))

    #expect(device.unmountLayers.map(\.bsdName) == ["disk9", "disk7"])
    #expect(device.ejectLayers.map(\.bsdName) == ["disk9", "disk7", "disk8", "disk6"])
    #expect(device.physicalBSDName == "disk6")
  }

  @Test("Empty batch returns zero counts")
  func emptyBatch() async throws {
    let session = try DiskSession()
    let result = await session.ejectAll([], options: .default)

    #expect(result.totalCount == 0)
    #expect(result.successCount == 0)
    #expect(result.failedCount == 0)
    #expect(result.results.isEmpty)
    #expect(result.totalDuration == 0)
  }

  @Test("Session invalidation prevents operations")
  func sessionInvalidation() async throws {
    let session = try DiskSession()
    await session.invalidate()

    // After invalidation, operations should fail
    let result = await session.unmount(path: "/Volumes/NonExistent")
    #expect(!result.success)
  }

  @Test("Invalid session preserves one structured outcome per physical device")
  func invalidSessionProgressIsGrouped() async throws {
    let sourceSession = try #require(DASessionCreate(kCFAllocatorDefault))
    let rootURL = URL(fileURLWithPath: "/") as CFURL
    let disk = try #require(DADiskCreateFromVolumePath(
      kCFAllocatorDefault,
      sourceSession,
      rootURL
    ))
    let volumes = [
      Volume(
        info: VolumeInfo(
          name: "Private Project Alpha",
          path: "/Volumes/Private Project Alpha",
          bsdName: "synthetic-a"
        ),
        disk: disk
      ),
      Volume(
        info: VolumeInfo(
          name: "Private Project Beta",
          path: "/Volumes/Private Project Beta",
          bsdName: "synthetic-b"
        ),
        disk: disk
      ),
    ]
    let session = try DiskSession()
    await session.invalidate()
    let recorder = ProgressRecorder()

    let result = await session.ejectAll(volumes) { event in
      await recorder.append(event)
    }
    let progress = await recorder.snapshot

    #expect(result.totalCount == 2)
    #expect(result.successCount == 0)
    #expect(result.failedCount == 2)
    #expect(progress.count == 1, "Two partitions on one whole disk must produce one workflow")
    guard case .completed(let deviceID, .failed(let failure, _)) = progress.first else {
      Issue.record("Expected one structured session failure")
      return
    }
    #expect(deviceID == failure.deviceID)
    #expect(failure.stage == .unmount)
    #expect(failure.category == .session)
  }
}

private actor ProgressRecorder {
  private var events: [DeviceEjectEvent] = []

  var snapshot: [DeviceEjectEvent] { events }

  func append(_ event: DeviceEjectEvent) {
    events.append(event)
  }
}

@Suite("EjectOptions Tests")
struct EjectOptionsTests {

  @Test("Default options are correct")
  func defaultOptions() {
    let options = EjectOptions.default
    #expect(!options.force)
    #expect(options.ejectPhysicalDevice)
  }

  @Test("Unmount only options are correct")
  func unmountOnlyOptions() {
    let options = EjectOptions.unmountOnly
    #expect(!options.force)
    #expect(!options.ejectPhysicalDevice)
  }

  @Test("Force eject options are correct")
  func forceEjectOptions() {
    let options = EjectOptions.forceEject
    #expect(options.force)
    #expect(options.ejectPhysicalDevice)
  }

  @Test("Custom options work")
  func customOptions() {
    let options = EjectOptions(force: true, ejectPhysicalDevice: false)
    #expect(options.force)
    #expect(!options.ejectPhysicalDevice)
  }
}

@Suite("DiskOperationResult Tests")
struct DiskOperationResultTests {

  @Test("Success result has no error")
  func successResult() {
    let result = DiskOperationResult(success: true, error: nil, duration: 0.1)
    #expect(result.success)
    #expect(result.error == nil)
    #expect(result.duration == 0.1)
  }

  @Test("Failure result has error")
  func failureResult() {
    let result = DiskOperationResult(success: false, error: .busy(message: "test"), duration: 0.2)
    #expect(!result.success)
    #expect(result.error != nil)
    if case .busy(let message) = result.error {
      #expect(message == "test")
    } else {
      Issue.record("Expected busy error")
    }
  }
}

@Suite("BatchEjectResult Tests")
struct BatchEjectResultTests {

  @Test("SingleEjectResult is Codable")
  func singleResultCodable() throws {
    let result = SingleEjectResult(
      volumeName: "USB Drive",
      volumePath: "/Volumes/USB Drive",
      bsdName: "disk2s1",
      success: true,
      errorMessage: nil,
      duration: 0.05
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(result)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(SingleEjectResult.self, from: data)

    #expect(decoded.volumeName == result.volumeName)
    #expect(decoded.volumePath == result.volumePath)
    #expect(decoded.bsdName == result.bsdName)
    #expect(decoded.success == result.success)
    #expect(decoded.errorMessage == result.errorMessage)
    #expect(decoded.duration == result.duration)
  }

  @Test("Failed result includes error message")
  func failedResultMessage() throws {
    let result = SingleEjectResult(
      volumeName: "Busy Drive",
      volumePath: "/Volumes/Busy Drive",
      bsdName: "disk3s1",
      success: false,
      errorMessage: "Spotlight is indexing",
      duration: 0.01
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(result)
    let json = String(data: data, encoding: .utf8)!

    #expect(json.contains("Spotlight is indexing"))
  }
}

@Suite("Integration Tests", .disabled("Requires external volumes"))
struct IntegrationTests {
  // These tests require actual external volumes and are disabled by default
  // Run manually when testing with real hardware

  @Test("Can enumerate real volumes")
  func enumerateRealVolumes() async throws {
    let session = try DiskSession()
    let volumes = await session.enumerateEjectableVolumes()

    for volume in volumes {
      print("Found: \(volume)")
      #expect(!volume.info.name.isEmpty)
      #expect(volume.info.path.hasPrefix("/Volumes/"))
    }
  }

  @Test("Can eject real volume")
  func ejectRealVolume() async throws {
    let session = try DiskSession()
    let volumes = await session.enumerateEjectableVolumes()

    guard let volume = volumes.first else {
      Issue.record("No external volumes to test with")
      return
    }

    print("Ejecting: \(volume.info.name)")
    let result = await session.unmount(volume)
    print("Result: success=\(result.success), duration=\(result.duration)s")

    // We can't guarantee success (volume might be in use)
    // but the operation should complete
    #expect(result.duration >= 0)
  }
}
