//
//  DiskSession.swift
//  SwiftDiskArbitration
//
//  Actor-based session management for DiskArbitration operations.
//  Provides thread-safe async/await APIs for disk unmounting and ejection.
//

import DiskArbitration
import Foundation
import Security

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

  /// Authorization reference for unmount operations
  /// This is required for unprivileged apps to unmount volumes
  private nonisolated(unsafe) var authRef: AuthorizationRef?

  /// Whether authorization has been granted
  public private(set) var isAuthorized: Bool = false

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

    // Free the authorization reference if we have one
    if let ref = authRef {
      AuthorizationFree(ref, [])
    }
  }

  // MARK: - Authorization

  /// Requests authorization to unmount removable volumes.
  ///
  /// This requests the `system.volume.removable.unmount` right from the system.
  /// A password dialog will be shown to the user if they are an admin.
  /// Once authorized, the authorization persists for the lifetime of this session.
  ///
  /// Call this once before attempting to eject volumes. For Stream Deck plugins,
  /// call this when the plugin initializes.
  ///
  /// - Throws: DiskError.authorizationFailed if authorization fails
  /// - Throws: DiskError.authorizationCancelled if user cancels the dialog
  public func requestAuthorization() throws {
    // Create authorization reference with default flags
    var authRefLocal: AuthorizationRef?
    var status = AuthorizationCreate(nil, nil, AuthorizationFlags(), &authRefLocal)

    guard status == errAuthorizationSuccess, let ref = authRefLocal else {
      print("[SwiftDiskArbitration] AuthorizationCreate failed with status: \(status)")
      throw DiskError.authorizationFailed(status: status)
    }

    // Request the specific right for unmounting removable volumes
    // This is what Finder and diskutil do behind the scenes
    let rightName = ("system.volume.removable.unmount" as NSString).utf8String!

    var rightItem = AuthorizationItem(
      name: rightName,
      valueLength: 0,
      value: nil,
      flags: 0
    )

    // Use withUnsafeMutablePointer to ensure the pointer remains valid
    status = withUnsafeMutablePointer(to: &rightItem) { rightItemPtr in
      var rights = AuthorizationRights(count: 1, items: rightItemPtr)

      // Flags to allow user interaction and extend rights
      let flags: AuthorizationFlags = [
        .interactionAllowed,  // Show password dialog if needed
        .extendRights  // Extend authorization to new rights
      ]

      print("[SwiftDiskArbitration] Requesting authorization for 'system.volume.removable.unmount'...")
      return AuthorizationCopyRights(ref, &rights, nil, flags, nil)
    }

    print("[SwiftDiskArbitration] AuthorizationCopyRights returned status: \(status)")

    if status == errAuthorizationSuccess {
      self.authRef = ref
      self.isAuthorized = true
      print("[SwiftDiskArbitration] Authorization granted!")
    } else if status == errAuthorizationCanceled {
      AuthorizationFree(ref, AuthorizationFlags())
      print("[SwiftDiskArbitration] User cancelled authorization")
      throw DiskError.authorizationCancelled
    } else {
      AuthorizationFree(ref, AuthorizationFlags())
      print("[SwiftDiskArbitration] Authorization failed with status: \(status)")
      throw DiskError.authorizationFailed(status: status)
    }
  }

  /// Checks if we're running with root privileges (sudo)
  public nonisolated var isRunningAsRoot: Bool {
    return geteuid() == 0
  }

  /// Checks if authorization is needed (not root and not already authorized)
  public var needsAuthorization: Bool {
    return !isRunningAsRoot && !isAuthorized
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

  /// Ejects all provided volumes in parallel.
  ///
  /// Uses Swift concurrency TaskGroup for true parallel execution.
  /// Each volume is unmounted (and optionally ejected) concurrently.
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

    // Execute all ejections in parallel using TaskGroup
    let results = await withTaskGroup(
      of: SingleEjectResult.self, returning: [SingleEjectResult].self
    ) { group in
      for volume in volumes {
        group.addTask {
          let result = await self.unmount(volume, options: options)
          return SingleEjectResult(
            volumeName: volume.info.name,
            volumePath: volume.info.path,
            success: result.success,
            errorMessage: result.error?.description,
            duration: result.duration
          )
        }
      }

      var collected: [SingleEjectResult] = []
      collected.reserveCapacity(volumes.count)
      for await result in group {
        collected.append(result)
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
