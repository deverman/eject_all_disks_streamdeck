//
//  DiskSession.swift
//  SwiftDiskArbitration
//
//  Actor-based session management for DiskArbitration operations.
//  Provides thread-safe async/await APIs for disk unmounting and ejection.
//
// ============================================================================
// SWIFT BEGINNER'S GUIDE TO THIS FILE
// ============================================================================
//
// WHY THIS IS AN ACTOR (not a class):
// ------------------------------------
// An `actor` is a Swift type that provides automatic thread safety.
// Only one piece of code can access an actor's state at a time.
//
// We need this because:
//   1. DiskArbitration callbacks come from a background queue
//   2. Multiple eject operations might run in parallel
//   3. We need to track session validity (`isValid`) safely
//
// Without an actor, we'd need manual locks, which are error-prone.
//
// KEY CONCEPTS:
// -------------
//
// 1. DASession LIFECYCLE
//    - DASessionCreate() creates a session with Apple's disk framework
//    - DASessionSetDispatchQueue() tells it where to deliver callbacks
//    - In deinit, we set the queue to nil to stop callbacks before cleanup
//
// 2. ISOLATED CLEANUP
//    Swift 6.2+ supports an `isolated deinit` for actors. The session remains
//    actor-isolated through cleanup, so it needs no `nonisolated(unsafe)` escape.
//
// 3. PHYSICAL DEVICE GROUPING (Performance Optimization)
//    A USB drive with 2 partitions appears as 2 volumes, but it's 1 device.
//    Without grouping: Eject vol1, then eject vol2 (redundant)
//    With grouping: Unmount both, eject device once (faster)
//
//    Example:
//      disk2s1 (Partition 1) ─┐
//                             ├─> disk2 (USB Drive) → Eject once
//      disk2s2 (Partition 2) ─┘
//
// 4. TaskGroup FOR PARALLEL EXECUTION
//    When ejecting multiple USB drives, we process them in parallel:
//    - Drive A and Drive B eject simultaneously
//    - Reduces total time from (A + B) to max(A, B)
//
// ============================================================================

import DiskArbitration
import Foundation
import OSLog

/// Result of ejecting multiple volumes
public struct BatchEjectResult: Sendable {
  /// Total number of volumes processed
  public let totalCount: Int

  /// Number of successfully ejected volumes
  public let successCount: Int

  /// Number of failed ejections
  public let failedCount: Int

  /// Individual results for each volume
  public let results: [SingleEjectResult]

  /// Total duration for all operations
  public let totalDuration: TimeInterval

  public init(
    totalCount: Int,
    successCount: Int,
    failedCount: Int,
    results: [SingleEjectResult],
    totalDuration: TimeInterval
  ) {
    self.totalCount = totalCount
    self.successCount = successCount
    self.failedCount = failedCount
    self.results = results
    self.totalDuration = totalDuration
  }
}

/// Result of ejecting a single volume
public struct SingleEjectResult: Sendable, Codable {
  /// Name of the volume
  public let volumeName: String

  /// Path to the volume
  public let volumePath: String

  /// BSD device name, safe to include in diagnostic logs (e.g., disk2s1)
  public let bsdName: String?

  /// Whether the ejection succeeded
  public let success: Bool

  /// Error message if failed
  public let errorMessage: String?

  /// Typed error category if failed. Prefer this over parsing `errorMessage`.
  public let errorCategory: DiskErrorCategory?

  /// Disk operation stage that produced the failure, when available.
  public let errorStage: DiskOperationStage?

  /// Raw DiskArbitration status retained for future diagnostics.
  public let rawStatus: DAReturn?

  /// Duration of this specific ejection
  public let duration: TimeInterval

  public init(
    volumeName: String,
    volumePath: String,
    bsdName: String?,
    success: Bool,
    errorMessage: String?,
    errorCategory: DiskErrorCategory? = nil,
    errorStage: DiskOperationStage? = nil,
    rawStatus: DAReturn? = nil,
    duration: TimeInterval
  ) {
    self.volumeName = volumeName
    self.volumePath = volumePath
    self.bsdName = bsdName
    self.success = success
    self.errorMessage = errorMessage
    self.errorCategory = errorCategory
    self.errorStage = errorStage
    self.rawStatus = rawStatus
    self.duration = duration
  }
}

/// Options for unmount/eject operations
public struct EjectOptions: Sendable {
  /// Force unmount even if files are open (may cause data loss)
  public var force: Bool

  /// Eject the physical device after unmounting (for USB drives, etc.)
  public var ejectPhysicalDevice: Bool

  /// Default options: no force, eject physical device
  public static let `default` = EjectOptions(force: false, ejectPhysicalDevice: true)

  /// Unmount only (don't physically eject)
  public static let unmountOnly = EjectOptions(force: false, ejectPhysicalDevice: false)

  /// Force eject (may cause data loss if files are open)
  public static let forceEject = EjectOptions(force: true, ejectPhysicalDevice: true)

  public init(force: Bool = false, ejectPhysicalDevice: Bool = true) {
    self.force = force
    self.ejectPhysicalDevice = ejectPhysicalDevice
  }
}

/// Actor that manages DiskArbitration session and provides async APIs.
///
/// Usage:
/// ```swift
/// let session = DiskSession()
/// let volumes = session.enumerateEjectableVolumes()
/// let results = await session.ejectAll(volumes)
/// ```
///
/// Thread Safety:
/// - All operations are isolated to this actor
/// - The underlying DASession is scheduled on a dedicated dispatch queue
/// - Callbacks are bridged to async/await using continuations
public actor DiskSession {
  /// The underlying DiskArbitration session
  private let daSession: DASession

  /// Dispatch queue for DiskArbitration callbacks
  private let callbackQueue: DispatchQueue

  /// Whether this session is still valid
  private var isValid: Bool = true

  /// Creates a new DiskSession
  /// - Throws: DiskError.sessionCreationFailed if session cannot be created
  public init() throws {
    guard let session = DASessionCreate(kCFAllocatorDefault) else {
      throw DiskError.sessionCreationFailed
    }

    self.daSession = session
    self.callbackQueue = DispatchQueue(
      label: "com.swiftdiskarbitration.callback",
      qos: .userInitiated
    )

    // Schedule the session on our callback queue
    // This is required for callbacks to be invoked
    DASessionSetDispatchQueue(session, callbackQueue)
  }

  isolated deinit {
    // Unschedule the session from the dispatch queue
    // This prevents callbacks from firing after deallocation
    DASessionSetDispatchQueue(daSession, nil)
  }

  // MARK: - Privileges

  /// Checks if we're running with root privileges (sudo)
  /// When true, disk operations will have full access to unmount/eject volumes.
  public nonisolated var isRunningAsRoot: Bool {
    return geteuid() == 0
  }

  // MARK: - Volume Enumeration

  /// Enumerates all ejectable external volumes.
  ///
  /// Returns volumes that are external, ejectable, or removable.
  /// Each volume includes a cached DADisk reference for fast ejection.
  ///
  /// - Returns: Array of ejectable volumes
  public func enumerateEjectableVolumes() -> [Volume] {
    return Volume.enumerateEjectableVolumes(session: daSession)
  }

  /// Returns the count of ejectable volumes (faster than full enumeration)
  public func ejectableVolumeCount() -> Int {
    return enumerateEjectableVolumes().count
  }

  // MARK: - Single Volume Operations

  /// Unmounts a single volume.
  ///
  /// - Parameters:
  ///   - volume: The volume to unmount
  ///   - options: Unmount/eject options
  /// - Returns: Result of the operation
  public func unmount(_ volume: Volume, options: EjectOptions = .default) async
    -> DiskOperationResult
  {
    guard isValid else {
      return DiskOperationResult(success: false, error: .sessionCreationFailed, duration: 0)
    }

    if options.ejectPhysicalDevice {
      guard let topology = PhysicalDiskResolver.resolve(volume.disk, session: daSession) else {
        let sourceBSDName = volume.info.bsdName ?? "unknown"
        diskOperationLog.error(
          "operation=resolve result=failure source=\(sourceBSDName, privacy: .public) category=unavailable_or_ambiguous"
        )
        return DiskOperationResult(
          success: false,
          error: .invalidDiskReference,
          duration: 0,
          stage: .unmount
        )
      }
      return await unmountResolvedDiskStackAndEject(
        topology,
        force: options.force
      )
    }

    var unmountOptions = kDADiskUnmountOptionDefault
    if options.force {
      unmountOptions |= kDADiskUnmountOptionForce
    }
    return await unmountDiskAsync(
      volume.disk,
      options: DADiskUnmountOptions(unmountOptions)
    )
  }

  /// Unmounts a volume by path.
  ///
  /// - Parameters:
  ///   - path: Path to the volume (e.g., "/Volumes/MyDrive")
  ///   - options: Unmount/eject options
  /// - Returns: Result of the operation
  public func unmount(path: String, options: EjectOptions = .default) async -> DiskOperationResult {
    guard isValid else {
      return DiskOperationResult(success: false, error: .sessionCreationFailed, duration: 0)
    }

    let url = URL(fileURLWithPath: path)
    guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, daSession, url as CFURL) else {
      return DiskOperationResult(
        success: false, error: .notFound(message: "Volume not found at \(path)"), duration: 0)
    }

    // Create a temporary Volume object for the operation
    let info = VolumeInfo(
      name: url.lastPathComponent,
      path: path,
      bsdName: DiskArbitrationUnsafeAdapter.bsdName(of: disk)
    )
    let volume = Volume(info: info, disk: disk)

    return await unmount(volume, options: options)
  }

  // MARK: - Batch Operations

  /// Represents a physical device and all its volumes.
  ///
  /// Safety invariant for `@unchecked Sendable`: `DADisk` is an immutable
  /// CoreFoundation reference used only as an identity/operation handle. Its
  /// DASession is scheduled once on `callbackQueue`; child tasks submit documented
  /// DiskArbitration operations and never mutate the handle's storage.
  private struct PhysicalDeviceGroup: @unchecked Sendable {
    let deviceID: PhysicalDeviceID

    /// All volumes on this physical device
    let volumes: [Volume]

    /// One ancestry chain per distinct mounted storage branch. Nil means
    /// resolution failed and the operation must fail closed.
    let topologies: [ResolvedDiskTopology]?
  }

  /// Groups volumes by their physical device (whole disk).
  /// This allows us to unmount and eject each physical device once,
  /// rather than processing each volume independently.
  ///
  /// - Parameter volumes: Array of volumes to group
  /// - Returns: Array of physical device groups
  private func groupVolumesByPhysicalDevice(_ volumes: [Volume]) -> [PhysicalDeviceGroup] {
    var groups: [String: PhysicalDeviceGroup] = [:]

    for volume in volumes {
      guard let resolvedDisk = PhysicalDiskResolver.resolve(volume.disk, session: daSession) else {
        // Preserve a result for the volume, but never submit an eject request
        // against the mounted volume as a fallback. That could succeed for a
        // synthesized APFS disk without making the hardware safe to unplug.
        let fallbackKey = volume.info.bsdName ?? UUID().uuidString
        diskOperationLog.error(
          "operation=resolve result=failure source=\(fallbackKey, privacy: .public) category=unavailable_or_ambiguous"
        )
        if let existingGroup = groups[fallbackKey] {
          var updatedVolumes = existingGroup.volumes
          updatedVolumes.append(volume)
          groups[fallbackKey] = PhysicalDeviceGroup(
            deviceID: existingGroup.deviceID,
            volumes: updatedVolumes,
            topologies: nil
          )
        } else {
          groups[fallbackKey] = PhysicalDeviceGroup(
            deviceID: PhysicalDeviceID(bsdName: fallbackKey),
            volumes: [volume],
            topologies: nil
          )
        }
        continue
      }

      let physicalBSDName = resolvedDisk.physicalBSDName

      // Add to existing group or create new one
      if let existingGroup = groups[physicalBSDName] {
        var updatedVolumes = existingGroup.volumes
        updatedVolumes.append(volume)
        var updatedTopologies = existingGroup.topologies ?? []
        if !updatedTopologies.contains(where: { $0.bsdNames == resolvedDisk.bsdNames }) {
          updatedTopologies.append(resolvedDisk)
        }
        groups[physicalBSDName] = PhysicalDeviceGroup(
          deviceID: PhysicalDeviceID(bsdName: physicalBSDName),
          volumes: updatedVolumes,
          topologies: updatedTopologies
        )
      } else {
        groups[physicalBSDName] = PhysicalDeviceGroup(
          deviceID: PhysicalDeviceID(bsdName: physicalBSDName),
          volumes: [volume],
          topologies: [resolvedDisk]
        )
      }
    }

    return Array(groups.values)
  }

  /// Ejects all provided volumes in parallel, grouped by physical device.
  ///
  /// Optimization: Groups volumes by their physical device (whole disk) first,
  /// then unmounts and ejects each physical device once. This reduces redundant
  /// operations when a disk has multiple partitions.
  ///
  /// Uses Swift concurrency TaskGroup for true parallel execution across
  /// different physical devices.
  ///
  /// - Parameters:
  ///   - volumes: Array of volumes to eject
  ///   - options: Unmount/eject options applied to all volumes
  /// - Returns: Batch result with individual results for each volume
  public func ejectAll(_ volumes: [Volume], options: EjectOptions = .default) async
    -> BatchEjectResult
  {
    await ejectAll(volumes, options: options, onProgress: { _ in })
  }

  /// Ejects all provided volumes while publishing physical-device progress as
  /// soon as each independent device changes stage or completes.
  public func ejectAll(
    _ volumes: [Volume],
    options: EjectOptions = .default,
    onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void
  ) async -> BatchEjectResult {
    let clock = ContinuousClock()
    let startedAt = clock.now

    guard !volumes.isEmpty else {
      return BatchEjectResult(
        totalCount: 0,
        successCount: 0,
        failedCount: 0,
        results: [],
        totalDuration: 0
      )
    }

    // Group before the validity check so even a session failure can preserve
    // per-physical-device progress and diagnostic identity.
    let deviceGroups = groupVolumesByPhysicalDevice(volumes)

    guard isValid else {
      let results = volumes.map { volume in
        SingleEjectResult(
          volumeName: volume.info.name,
          volumePath: volume.info.path,
          bsdName: volume.info.bsdName,
          success: false,
          errorMessage: "Session is invalid",
          errorCategory: .session,
          duration: 0
        )
      }
      for deviceGroup in deviceGroups {
        let failure = DeviceEjectFailure(
          deviceID: deviceGroup.deviceID,
          stage: .unmount,
          category: .session,
          rawStatus: nil
        )
        await onProgress(.completed(
          deviceGroup.deviceID,
          .failed(failure, duration: 0)
        ))
      }
      return BatchEjectResult(
        totalCount: volumes.count,
        successCount: 0,
        failedCount: volumes.count,
        results: results,
        totalDuration: 0
      )
    }

    // PRIVACY: We don't log volume names as they may contain sensitive information.
    // Only log counts, not names like "ConfidentialProject" or "ClientBackup".

    // Process each physical device in parallel
    let results = await withTaskGroup(
      of: [SingleEjectResult].self, returning: [SingleEjectResult].self
    ) { group in
      for deviceGroup in deviceGroups {
        group.addTask {
          // Eject this entire physical device (all volumes on it)
          let deviceResult = await self.ejectPhysicalDevice(
            deviceGroup,
            options: options,
            onProgress: onProgress
          )
          return deviceResult
        }
      }

      var collected: [SingleEjectResult] = []
      collected.reserveCapacity(volumes.count)
      for await groupResults in group {
        collected.append(contentsOf: groupResults)
      }
      return collected
    }

    let totalDuration = startedAt.duration(to: clock.now).diskOperationTimeInterval
    let successCount = results.filter(\.success).count

    return BatchEjectResult(
      totalCount: volumes.count,
      successCount: successCount,
      failedCount: volumes.count - successCount,
      results: results,
      totalDuration: totalDuration
    )
  }

  /// Ejects a physical device and all its volumes.
  ///
  /// This method unmounts each distinct innermost whole-media branch, then
  /// ejects every unique synthesized layer before ejecting the physical device
  /// once, within a single overall time budget.
  ///
  /// - Parameters:
  ///   - deviceGroup: The physical device group to eject
  ///   - options: Unmount/eject options
  /// - Returns: Array of results for each volume in the group
  private func ejectPhysicalDevice(
    _ deviceGroup: PhysicalDeviceGroup,
    options: EjectOptions,
    onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void
  ) async -> [SingleEjectResult] {
    // If we're ejecting the physical device
    if options.ejectPhysicalDevice {
      guard
        let topologies = deviceGroup.topologies,
        let deviceTopology = ResolvedDeviceEjectTopology(topologies: topologies)
      else {
        let error = DiskError.invalidDiskReference
        let failure = DeviceEjectFailure(
          deviceID: deviceGroup.deviceID,
          stage: .unmount,
          category: error.category,
          rawStatus: nil
        )
        await onProgress(.unmountStarted(deviceGroup.deviceID))
        await onProgress(.completed(
          deviceGroup.deviceID,
          .failed(failure, duration: 0)
        ))
        return deviceGroup.volumes.map { volume in
          SingleEjectResult(
            volumeName: volume.info.name,
            volumePath: volume.info.path,
            bsdName: volume.info.bsdName,
            success: false,
            errorMessage: error.description,
            errorCategory: error.category,
            errorStage: .unmount,
            rawStatus: nil,
            duration: 0
          )
        }
      }

      let result = await unmountResolvedDeviceTopologyAndEject(
        deviceTopology,
        force: options.force,
        deviceID: deviceGroup.deviceID,
        onProgress: onProgress
      )

      // Return the same result for all volumes in this group
      return deviceGroup.volumes.map { volume in
        SingleEjectResult(
          volumeName: volume.info.name,
          volumePath: volume.info.path,
          bsdName: volume.info.bsdName,
          success: result.success,
          errorMessage: result.error?.description,
          errorCategory: result.error?.category,
          errorStage: result.stage,
          rawStatus: result.rawStatus,
          duration: result.duration
        )
      }
    } else {
      // Unmount-only mode: unmount each volume individually
      // (This is less common, but we support it for backwards compatibility)
      var results: [SingleEjectResult] = []
      await onProgress(.unmountStarted(deviceGroup.deviceID))
      for volume in deviceGroup.volumes {
        let result = await unmount(volume, options: options)
        results.append(
          SingleEjectResult(
            volumeName: volume.info.name,
            volumePath: volume.info.path,
            bsdName: volume.info.bsdName,
            success: result.success,
            errorMessage: result.error?.description,
            errorCategory: result.error?.category,
            errorStage: result.stage,
            rawStatus: result.rawStatus,
            duration: result.duration
          )
        )
      }
      let firstFailure = results.first(where: { !$0.success })
      let outcome: DeviceEjectOutcome
      if results.allSatisfy(\.success) {
        outcome = .unmounted(duration: results.map(\.duration).max() ?? 0)
      } else if firstFailure?.errorCategory == .timeout {
        outcome = .timedOut(stage: .unmount, duration: firstFailure?.duration ?? 0)
      } else if firstFailure?.errorCategory == .cancelled {
        outcome = .cancelled(stage: .unmount, duration: firstFailure?.duration ?? 0)
      } else {
        outcome = .failed(
          DeviceEjectFailure(
            deviceID: deviceGroup.deviceID,
            stage: .unmount,
            category: firstFailure?.errorCategory ?? .other,
            rawStatus: firstFailure?.rawStatus
          ),
          duration: firstFailure?.duration ?? 0
        )
      }
      await onProgress(.completed(deviceGroup.deviceID, outcome))
      return results
    }
  }

  /// Ejects all currently mounted external volumes.
  ///
  /// Convenience method that combines enumeration and ejection.
  ///
  /// - Parameter options: Unmount/eject options
  /// - Returns: Batch result with individual results for each volume
  public func ejectAllExternal(options: EjectOptions = .default) async -> BatchEjectResult {
    let volumes = enumerateEjectableVolumes()
    return await ejectAll(volumes, options: options)
  }

  // MARK: - Session Management

  /// Invalidates this session. No further operations will succeed.
  public func invalidate() {
    isValid = false
    DASessionSetDispatchQueue(daSession, nil)
  }
}

// MARK: - Shared Session

extension DiskSession {
  /// Shared session for convenience, or nil if the DiskArbitration session
  /// could not be created.
  ///
  /// Deliberately optional rather than trapping: a failure to create the
  /// session should degrade gracefully (e.g., a Stream Deck key showing an
  /// error state), not crash the host process.
  ///
  /// Use a dedicated session for long-running applications that need precise
  /// lifecycle control.
  public static let shared: DiskSession? = try? DiskSession()
}
