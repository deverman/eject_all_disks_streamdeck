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

import AppKit
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
internal let debugCallbacks = true  // Enabled for diagnosing ejection issues

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

// MARK: - NSWorkspace Unmount

/// Unmounts a volume using NSWorkspace (same mechanism as Finder)
/// This works for user-mounted external drives without requiring admin privileges
///
/// - Parameters:
///   - url: The URL of the volume to unmount
///   - eject: Whether to also eject the device
/// - Returns: Result of the unmount operation
internal func unmountWithWorkspace(at url: URL, eject: Bool) -> DiskOperationResult {
  let startTime = Date()

  // NSWorkspace.unmountAndEjectDevice uses the same mechanism as Finder
  // It handles authorization automatically for user-mounted drives
  // Note: unmountAndEjectDevice both unmounts AND ejects for removable media
  let success = NSWorkspace.shared.unmountAndEjectDevice(at: url)

  let duration = Date().timeIntervalSince(startTime)

  if success {
    if debugCallbacks {
      print("[SwiftDiskArbitration] NSWorkspace unmount success for \(url.path)")
    }
    return DiskOperationResult(success: true, error: nil, duration: duration)
  } else {
    if debugCallbacks {
      print("[SwiftDiskArbitration] NSWorkspace unmount failed for \(url.path)")
    }
    // NSWorkspace doesn't provide detailed error info, so we return a generic error
    return DiskOperationResult(
      success: false,
      error: .generalError(message: "Failed to unmount \(url.lastPathComponent)"),
      duration: duration
    )
  }
}

// MARK: - Combined Operations

/// Unmounts and optionally ejects a volume
///
/// Uses NSWorkspace (Finder's mechanism) for unprivileged unmount, which works
/// for user-mounted external drives. Falls back to DADiskUnmount for force unmount.
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

  // For non-force unmounts, use NSWorkspace which works like Finder
  // This doesn't require elevated privileges for user-mounted drives
  if !force {
    let result = unmountWithWorkspace(at: volume.url, eject: ejectAfterUnmount)
    return result
  }

  // For force unmount, we need to use DADiskUnmount with the force flag
  // This may still require privileges but it's the only way to force

  // Build unmount options
  var unmountOptions = kDADiskUnmountOptionDefault
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  // If we have a whole disk and want to eject, unmount all partitions
  if ejectAfterUnmount, volume.wholeDisk != nil {
    unmountOptions |= kDADiskUnmountOptionWhole
  }

  // Step 1: Unmount with DADiskUnmount (for force option)
  let unmountResult = await unmountDiskAsync(
    volume.disk,
    options: DADiskUnmountOptions(unmountOptions)
  )

  guard unmountResult.success else {
    return unmountResult
  }

  // Step 2: Eject (if requested and we have a whole disk)
  if ejectAfterUnmount, let wholeDisk = volume.wholeDisk {
    let ejectResult = await ejectDiskAsync(wholeDisk)
    let totalDuration = Date().timeIntervalSince(startTime)

    if ejectResult.success {
      return DiskOperationResult(success: true, error: nil, duration: totalDuration)
    } else {
      // Unmount succeeded but eject failed
      return DiskOperationResult(
        success: false,
        error: ejectResult.error,
        duration: totalDuration
      )
    }
  }

  return unmountResult
}
