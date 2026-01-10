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
// 2. nonisolated(unsafe)
//    The `daSession` property is marked `nonisolated(unsafe)` because:
//    - We need to access it in `deinit` (which runs outside actor isolation)
//    - DASession is thread-safe, so this is actually safe
//    - Swift 6 requires us to be explicit about this
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
}

/// Result of ejecting a single volume
public struct SingleEjectResult: Sendable, Codable {
  /// Name of the volume
  public let volumeName: String

  /// Path to the volume
  public let volumePath: String

  /// Whether the ejection succeeded
  public let success: Bool

  /// Error message if failed
  public let errorMessage: String?

  /// Duration of this specific ejection
  public let duration: TimeInterval
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
  /// Marked nonisolated(unsafe) to allow cleanup in deinit.
  /// This is safe because DASession is thread-safe and we only access it
  /// for cleanup when no other operations can be in flight.
  private nonisolated(unsafe) let daSession: DASession

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

  deinit {
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

    return await unmountAndEjectAsync(
      volume,
      ejectAfterUnmount: options.ejectPhysicalDevice,
      force: options.force
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
      bsdName: DADiskGetBSDName(disk).map { String(cString: $0) }
    )
    let volume = Volume(info: info, disk: disk)

    return await unmount(volume, options: options)
  }

  // MARK: - Batch Operations

  /// Represents a physical device and all its volumes
  /// Marked @unchecked Sendable because DADisk is thread-safe for our use case
  private struct PhysicalDeviceGroup: @unchecked Sendable {
    /// BSD name of the whole disk (e.g., "disk2")
    let wholeDiskBSDName: String

    /// All volumes on this physical device
    let volumes: [Volume]

    /// The whole disk reference (same for all volumes in this group)
    let wholeDisk: DADisk
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
      // Get the whole disk BSD name
      guard let wholeDiskBSDName = volume.wholeDiskBSDName,
        let wholeDisk = volume.wholeDisk
      else {
        // If we can't get the whole disk, create a single-volume group
        // using the volume's own BSD name as a fallback
        let fallbackKey = volume.info.bsdName ?? UUID().uuidString
        groups[fallbackKey] = PhysicalDeviceGroup(
          wholeDiskBSDName: fallbackKey,
          volumes: [volume],
          wholeDisk: volume.disk
        )
        continue
      }

      // Add to existing group or create new one
      if let existingGroup = groups[wholeDiskBSDName] {
        var updatedVolumes = existingGroup.volumes
        updatedVolumes.append(volume)
        groups[wholeDiskBSDName] = PhysicalDeviceGroup(
          wholeDiskBSDName: wholeDiskBSDName,
          volumes: updatedVolumes,
          wholeDisk: wholeDisk
        )
      } else {
        groups[wholeDiskBSDName] = PhysicalDeviceGroup(
          wholeDiskBSDName: wholeDiskBSDName,
          volumes: [volume],
          wholeDisk: wholeDisk
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
    let startTime = Date()

    guard !volumes.isEmpty else {
      return BatchEjectResult(
        totalCount: 0,
        successCount: 0,
        failedCount: 0,
        results: [],
        totalDuration: 0
      )
    }

    guard isValid else {
      let results = volumes.map { volume in
        SingleEjectResult(
          volumeName: volume.info.name,
          volumePath: volume.info.path,
          success: false,
          errorMessage: "Session is invalid",
          duration: 0
        )
      }
      return BatchEjectResult(
        totalCount: volumes.count,
        successCount: 0,
        failedCount: volumes.count,
        results: results,
        totalDuration: 0
      )
    }

    // Group volumes by their physical device
    let deviceGroups = groupVolumesByPhysicalDevice(volumes)

    // Debug: Print grouping information
    if deviceGroups.count < volumes.count {
      print(
        "[DiskSession] Grouped \(volumes.count) volumes into \(deviceGroups.count) physical device(s)"
      )
      for group in deviceGroups {
        print(
          "  - \(group.wholeDiskBSDName): \(group.volumes.count) volume(s) (\(group.volumes.map { $0.info.name }.joined(separator: ", ")))"
        )
      }
    }

    // Process each physical device in parallel
    let results = await withTaskGroup(
      of: [SingleEjectResult].self, returning: [SingleEjectResult].self
    ) { group in
      for deviceGroup in deviceGroups {
        group.addTask {
          // Eject this entire physical device (all volumes on it)
          let deviceResult = await self.ejectPhysicalDevice(
            deviceGroup,
            options: options
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

    let totalDuration = Date().timeIntervalSince(startTime)
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
  /// This method unmounts all volumes on the device with kDADiskUnmountOptionWhole,
  /// then ejects the physical device once.
  ///
  /// - Parameters:
  ///   - deviceGroup: The physical device group to eject
  ///   - options: Unmount/eject options
  /// - Returns: Array of results for each volume in the group
  private func ejectPhysicalDevice(
    _ deviceGroup: PhysicalDeviceGroup,
    options: EjectOptions
  ) async -> [SingleEjectResult] {
    let operationStart = Date()

    // If we're ejecting the physical device
    if options.ejectPhysicalDevice {
      // Step 1: Unmount all volumes on the whole disk
      var unmountOptions = kDADiskUnmountOptionWhole
      if options.force {
        unmountOptions |= kDADiskUnmountOptionForce
      }

      let unmountResult = await unmountDiskAsync(
        deviceGroup.wholeDisk,
        options: DADiskUnmountOptions(unmountOptions)
      )

      // If unmount failed, return failure for all volumes in this group
      guard unmountResult.success else {
        return deviceGroup.volumes.map { volume in
          SingleEjectResult(
            volumeName: volume.info.name,
            volumePath: volume.info.path,
            success: false,
            errorMessage: unmountResult.error?.description ?? "Unmount failed",
            duration: unmountResult.duration
          )
        }
      }

      // Step 2: Eject the physical device
      let ejectResult = await ejectDiskAsync(deviceGroup.wholeDisk)
      let totalDuration = Date().timeIntervalSince(operationStart)

      // Return the same result for all volumes in this group
      return deviceGroup.volumes.map { volume in
        SingleEjectResult(
          volumeName: volume.info.name,
          volumePath: volume.info.path,
          success: ejectResult.success,
          errorMessage: ejectResult.error?.description,
          duration: totalDuration
        )
      }
    } else {
      // Unmount-only mode: unmount each volume individually
      // (This is less common, but we support it for backwards compatibility)
      var results: [SingleEjectResult] = []
      for volume in deviceGroup.volumes {
        let result = await unmount(volume, options: options)
        results.append(
          SingleEjectResult(
            volumeName: volume.info.name,
            volumePath: volume.info.path,
            success: result.success,
            errorMessage: result.error?.description,
            duration: result.duration
          )
        )
      }
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
  /// Shared session for convenience.
  /// Use a dedicated session for long-running applications that need precise lifecycle control.
  public static let shared: DiskSession = {
    do {
      return try DiskSession()
    } catch {
      fatalError("Failed to create shared DiskSession: \(error)")
    }
  }()
}
