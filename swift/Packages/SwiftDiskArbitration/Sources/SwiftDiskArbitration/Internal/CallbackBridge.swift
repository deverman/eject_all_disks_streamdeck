//
//  CallbackBridge.swift
//  SwiftDiskArbitration
//
//  Bridges C-style DiskArbitration callbacks to Swift async/await continuations.
//
//  Memory Management Strategy:
//  - We use Unmanaged.passRetained() to prevent the context from being deallocated
//    before the callback fires
//  - The callback uses takeRetainedValue() to balance the retain and allow deallocation
//  - Each continuation is guaranteed to resume exactly once
//

import DiskArbitration
import Foundation

/// Result of an unmount or eject operation
public struct DiskOperationResult: Sendable {
  /// Whether the operation succeeded
  public let success: Bool

  /// Error if the operation failed, nil on success
  public let error: DiskError?

  /// Duration of the operation in seconds
  public let duration: TimeInterval

  internal init(success: Bool, error: DiskError?, duration: TimeInterval) {
    self.success = success
    self.error = error
    self.duration = duration
  }
}

// MARK: - Callback Context

/// Context object that holds the continuation for async bridging.
/// This class is used to pass Swift context through the C void* parameter.
///
/// Memory Safety:
/// - Allocated with passRetained() before the C call
/// - Deallocated with takeRetainedValue() in the callback
/// - Guarantees exactly one resume of the continuation
internal final class UnmountCallbackContext {
  let continuation: CheckedContinuation<DiskOperationResult, Never>
  let startTime: Date

  init(continuation: CheckedContinuation<DiskOperationResult, Never>) {
    self.continuation = continuation
    self.startTime = Date()
  }
}

internal final class EjectCallbackContext {
  let continuation: CheckedContinuation<DiskOperationResult, Never>
  let startTime: Date

  init(continuation: CheckedContinuation<DiskOperationResult, Never>) {
    self.continuation = continuation
    self.startTime = Date()
  }
}

// MARK: - C Callback Functions

/// Enable debug output for troubleshooting
/// Set to true to see detailed callback information
internal let debugCallbacks = false  // Set to true for debugging

/// C callback for DADiskUnmount
/// This function has @convention(c) semantics and cannot capture Swift context directly
internal let unmountCallback: DADiskUnmountCallback = { disk, dissenter, context in
  guard let context = context else {
    // This should never happen if we set up the call correctly
    if debugCallbacks {
      print("[SwiftDiskArbitration] ERROR: unmountCallback received nil context!")
    }
    return
  }

  // Retrieve and release the context object (balances passRetained)
  let ctx = Unmanaged<UnmountCallbackContext>.fromOpaque(context).takeRetainedValue()
  let duration = Date().timeIntervalSince(ctx.startTime)

  // Debug: print what we received
  if debugCallbacks {
    if let dissenter = dissenter {
      let status = DADissenterGetStatus(dissenter)
      let statusStr = DADissenterGetStatusString(dissenter) as String? ?? "nil"
      print(
        "[SwiftDiskArbitration] unmountCallback: dissenter status=0x\(String(status, radix: 16)), message=\(statusStr)"
      )
    } else {
      print("[SwiftDiskArbitration] unmountCallback: success (no dissenter)")
    }
  }

  let result: DiskOperationResult
  if let error = DiskError.from(dissenter: dissenter) {
    result = DiskOperationResult(success: false, error: error, duration: duration)
  } else {
    result = DiskOperationResult(success: true, error: nil, duration: duration)
  }

  // Resume the continuation exactly once
  ctx.continuation.resume(returning: result)
}

/// C callback for DADiskEject
internal let ejectCallback: DADiskEjectCallback = { disk, dissenter, context in
  guard let context = context else {
    if debugCallbacks {
      print("[SwiftDiskArbitration] ERROR: ejectCallback received nil context!")
    }
    return
  }

  let ctx = Unmanaged<EjectCallbackContext>.fromOpaque(context).takeRetainedValue()
  let duration = Date().timeIntervalSince(ctx.startTime)

  // Debug: print what we received
  if debugCallbacks {
    if let dissenter = dissenter {
      let status = DADissenterGetStatus(dissenter)
      let statusStr = DADissenterGetStatusString(dissenter) as String? ?? "nil"
      print(
        "[SwiftDiskArbitration] ejectCallback: dissenter status=0x\(String(status, radix: 16)), message=\(statusStr)"
      )
    } else {
      print("[SwiftDiskArbitration] ejectCallback: success (no dissenter)")
    }
  }

  let result: DiskOperationResult
  if let error = DiskError.from(dissenter: dissenter) {
    result = DiskOperationResult(success: false, error: error, duration: duration)
  } else {
    result = DiskOperationResult(success: true, error: nil, duration: duration)
  }

  ctx.continuation.resume(returning: result)
}

// MARK: - Async Wrappers

/// Unmounts a disk asynchronously using DADiskUnmount
///
/// - Parameters:
///   - disk: The DADisk to unmount
///   - options: Unmount options (default or force)
/// - Returns: Result of the unmount operation
internal func unmountDiskAsync(
  _ disk: DADisk,
  options: DADiskUnmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionDefault)
) async -> DiskOperationResult {
  await withCheckedContinuation { continuation in
    let context = UnmountCallbackContext(continuation: continuation)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()

    DADiskUnmount(disk, options, unmountCallback, contextPtr)
  }
}

/// Ejects a disk asynchronously using DADiskEject
///
/// - Parameters:
///   - disk: The DADisk to eject (should be whole disk for physical ejection)
///   - options: Eject options
/// - Returns: Result of the eject operation
internal func ejectDiskAsync(
  _ disk: DADisk,
  options: DADiskEjectOptions = DADiskEjectOptions(kDADiskEjectOptionDefault)
) async -> DiskOperationResult {
  await withCheckedContinuation { continuation in
    let context = EjectCallbackContext(continuation: continuation)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()

    DADiskEject(disk, options, ejectCallback, contextPtr)
  }
}

// MARK: - Combined Operations

/// Unmounts and optionally ejects a volume.
///
/// For external drives, uses DADiskEject directly on the whole disk which
/// handles unmounting internally. This is more reliable than DADiskUnmount
/// for removable media.
///
/// NOTE: This requires Full Disk Access permission in System Settings.
/// Grant access to the binary at: System Settings → Privacy & Security → Full Disk Access
///
/// - Parameters:
///   - volume: The volume to unmount/eject
///   - ejectAfterUnmount: Whether to eject the physical device after unmounting
///   - force: Whether to force unmount even if files are open
/// - Returns: Result of the operation
internal func unmountAndEjectAsync(
  _ volume: Volume,
  ejectAfterUnmount: Bool,
  force: Bool
) async -> DiskOperationResult {
  let startTime = Date()

  // For ejection of external drives, unmount all volumes on the whole disk first,
  // then eject the physical device
  if ejectAfterUnmount, let wholeDisk = volume.wholeDisk {
    // Get BSD name of whole disk for debugging
    let wholeDiskBSD: String
    if let bsdName = DADiskGetBSDName(wholeDisk) {
      wholeDiskBSD = String(cString: bsdName)
    } else {
      wholeDiskBSD = "unknown"
    }

    if debugCallbacks {
      print(
        "[SwiftDiskArbitration] Step 1: Unmounting whole disk \(wholeDiskBSD) for volume \(volume.info.name) (\(volume.info.bsdName ?? "?"))"
      )
    }

    // Step 1: Unmount all volumes on the whole disk
    var unmountOptions = kDADiskUnmountOptionWhole
    if force {
      unmountOptions |= kDADiskUnmountOptionForce
    }

    let unmountResult = await unmountDiskAsync(
      wholeDisk,
      options: DADiskUnmountOptions(unmountOptions)
    )

    guard unmountResult.success else {
      if debugCallbacks {
        print("[SwiftDiskArbitration] Unmount failed: \(unmountResult.error?.description ?? "unknown")")
      }
      return unmountResult
    }

    if debugCallbacks {
      print("[SwiftDiskArbitration] Step 2: Ejecting whole disk \(wholeDiskBSD)")
    }

    // Step 2: Eject the physical device
    let ejectResult = await ejectDiskAsync(wholeDisk)
    let totalDuration = Date().timeIntervalSince(startTime)

    if ejectResult.success {
      return DiskOperationResult(success: true, error: nil, duration: totalDuration)
    } else {
      return DiskOperationResult(
        success: false,
        error: ejectResult.error,
        duration: totalDuration
      )
    }
  }

  // For unmount-only (no physical ejection), use DADiskUnmount
  var unmountOptions = kDADiskUnmountOptionDefault
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  if debugCallbacks {
    print("[SwiftDiskArbitration] Using DADiskUnmount for \(volume.info.name)")
  }

  let unmountResult = await unmountDiskAsync(
    volume.disk,
    options: DADiskUnmountOptions(unmountOptions)
  )

  return unmountResult
}
