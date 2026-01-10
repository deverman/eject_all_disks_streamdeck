//
//  CallbackBridge.swift
//  SwiftDiskArbitration
//
//  Bridges C-style DiskArbitration callbacks to Swift async/await continuations.
//
// ============================================================================
// SWIFT BEGINNER'S GUIDE TO THIS FILE
// ============================================================================
//
// WHY THIS FILE IS COMPLEX:
// -------------------------
// Apple's DiskArbitration framework is written in C, not Swift. To use it,
// we need to bridge between two very different programming models:
//
//   C callbacks:     "Call this function when done" (old style)
//   Swift async:     "await this operation" (modern style)
//
// This file converts C callbacks into Swift's async/await pattern.
//
// KEY CONCEPTS EXPLAINED:
// -----------------------
//
// 1. CALLBACKS vs ASYNC/AWAIT
//    In C, you pass a function pointer that gets called when work completes.
//    In Swift, you use `await` which pauses until work completes.
//    A "continuation" bridges these: it's a handle that lets you resume
//    the awaiting code when the C callback fires.
//
// 2. WHY WE NEED Unmanaged<T>
//    C functions accept a `void*` (raw pointer) to pass context around.
//    Swift objects are memory-managed (ARC), so we can't just cast them.
//    `Unmanaged` lets us:
//      - passRetained(): Convert Swift object → raw pointer (prevents dealloc)
//      - takeRetainedValue(): Convert raw pointer → Swift object (allows dealloc)
//
// 3. WHY TWO CONTEXT CLASSES (UnmountCallbackContext, EjectCallbackContext)
//    Each holds a continuation for its specific operation. They're identical
//    in structure but kept separate for type safety with the C callbacks.
//
// 4. @convention(c) CALLBACKS
//    The `unmountCallback` and `ejectCallback` constants are C-compatible
//    function pointers. They cannot capture Swift variables (no closures),
//    which is why we pass context through the void* parameter.
//
// MEMORY SAFETY FLOW:
// -------------------
//   1. Create context object with continuation
//   2. passRetained() → keeps object alive, gives us void*
//   3. Pass void* to C function (DADiskUnmount/DADiskEject)
//   4. C calls our callback with the void*
//   5. takeRetainedValue() → gets object back, balances retain
//   6. Resume continuation → Swift code continues after await
//   7. Context object deallocates (balanced retain/release)
//
// ============================================================================

import DiskArbitration
import Foundation

// MARK: - Timeout Configuration

/// Timeout for disk operations in seconds.
/// This prevents the plugin from hanging indefinitely if a drive is unresponsive.
internal let diskOperationTimeoutSeconds: TimeInterval = 30.0

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
/// Set to false in production to reduce console noise
internal let debugCallbacks = false

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
        "[SwiftDiskArbitration] unmountCallback: dissenter status=0x\(String(status, radix: 16)), message=\(statusStr), duration=\(String(format: "%.4f", duration))s"
      )
    } else {
      print("[SwiftDiskArbitration] unmountCallback: success (no dissenter), duration=\(String(format: "%.4f", duration))s")
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
        "[SwiftDiskArbitration] ejectCallback: dissenter status=0x\(String(status, radix: 16)), message=\(statusStr), duration=\(String(format: "%.4f", duration))s"
      )
    } else {
      print("[SwiftDiskArbitration] ejectCallback: success (no dissenter), duration=\(String(format: "%.4f", duration))s")
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

/// Unmounts a disk asynchronously using DADiskUnmount with timeout protection.
///
/// Thread Safety: DADisk is a Core Foundation type that is thread-safe.
/// This nonisolated function can be safely called from any isolation domain.
///
/// - Parameters:
///   - disk: The DADisk to unmount (thread-safe CFType)
///   - options: Unmount options (default or force)
///   - timeout: Maximum time to wait for the operation (default: 30 seconds)
/// - Returns: Result of the unmount operation
nonisolated internal func unmountDiskAsync(
  _ disk: DADisk,
  options: DADiskUnmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionDefault),
  timeout: TimeInterval = diskOperationTimeoutSeconds
) async -> DiskOperationResult {
  let startTime = Date()

  // Race the actual operation against a timeout
  return await withTaskGroup(of: DiskOperationResult.self) { group in
    // Task 1: The actual unmount operation
    group.addTask {
      await withCheckedContinuation { continuation in
        let context = UnmountCallbackContext(continuation: continuation)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        DADiskUnmount(disk, options, unmountCallback, contextPtr)
      }
    }

    // Task 2: Timeout watchdog
    group.addTask {
      try? await Task.sleep(for: .seconds(timeout))
      return DiskOperationResult(
        success: false,
        error: .timeout,
        duration: Date().timeIntervalSince(startTime)
      )
    }

    // Return whichever finishes first
    let result = await group.next()!
    group.cancelAll()
    return result
  }
}

/// Ejects a disk asynchronously using DADiskEject with timeout protection.
///
/// Thread Safety: DADisk is a Core Foundation type that is thread-safe.
/// This nonisolated function can be safely called from any isolation domain.
///
/// - Parameters:
///   - disk: The DADisk to eject (should be whole disk for physical ejection, thread-safe CFType)
///   - options: Eject options
///   - timeout: Maximum time to wait for the operation (default: 30 seconds)
/// - Returns: Result of the eject operation
nonisolated internal func ejectDiskAsync(
  _ disk: DADisk,
  options: DADiskEjectOptions = DADiskEjectOptions(kDADiskEjectOptionDefault),
  timeout: TimeInterval = diskOperationTimeoutSeconds
) async -> DiskOperationResult {
  let startTime = Date()

  // Race the actual operation against a timeout
  return await withTaskGroup(of: DiskOperationResult.self) { group in
    // Task 1: The actual eject operation
    group.addTask {
      await withCheckedContinuation { continuation in
        let context = EjectCallbackContext(continuation: continuation)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        DADiskEject(disk, options, ejectCallback, contextPtr)
      }
    }

    // Task 2: Timeout watchdog
    group.addTask {
      try? await Task.sleep(for: .seconds(timeout))
      return DiskOperationResult(
        success: false,
        error: .timeout,
        duration: Date().timeIntervalSince(startTime)
      )
    }

    // Return whichever finishes first
    let result = await group.next()!
    group.cancelAll()
    return result
  }
}

// MARK: - Combined Operations

/// Unmounts and optionally ejects a volume.
///
/// For external drives, uses DADiskEject directly on the whole disk which
/// handles unmounting internally. This is more reliable than DADiskUnmount
/// for removable media.
///
/// Thread Safety: This function is nonisolated and can be safely called from
/// any isolation domain. DADisk references are thread-safe CFTypes.
///
/// NOTE: This requires Full Disk Access permission in System Settings.
/// Grant access to the binary at: System Settings → Privacy & Security → Full Disk Access
///
/// - Parameters:
///   - volume: The volume to unmount/eject
///   - ejectAfterUnmount: Whether to eject the physical device after unmounting
///   - force: Whether to force unmount even if files are open
/// - Returns: Result of the operation
nonisolated internal func unmountAndEjectAsync(
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
      // PRIVACY: Use BSD name only, not user-visible volume name
      print(
        "[SwiftDiskArbitration] Step 1: Unmounting whole disk \(wholeDiskBSD) for volume \(volume.info.bsdName ?? "?")"
      )
    }

    // Step 1: Unmount all volumes on the whole disk
    var unmountOptions = kDADiskUnmountOptionWhole
    if force {
      unmountOptions |= kDADiskUnmountOptionForce
    }

    let unmountStart = Date()
    let unmountResult = await unmountDiskAsync(
      wholeDisk,
      options: DADiskUnmountOptions(unmountOptions)
    )
    let unmountElapsed = Date().timeIntervalSince(unmountStart)

    guard unmountResult.success else {
      if debugCallbacks {
        print("[SwiftDiskArbitration] Unmount failed: \(unmountResult.error?.description ?? "unknown"), elapsed=\(String(format: "%.4f", unmountElapsed))s")
      }
      return unmountResult
    }

    if debugCallbacks {
      print("[SwiftDiskArbitration] Step 2: Ejecting whole disk \(wholeDiskBSD) (unmount took \(String(format: "%.4f", unmountElapsed))s)")
    }

    // Step 2: Eject the physical device
    let ejectStart = Date()
    let ejectResult = await ejectDiskAsync(wholeDisk)
    let ejectElapsed = Date().timeIntervalSince(ejectStart)
    let totalDuration = Date().timeIntervalSince(startTime)

    if debugCallbacks {
      print("[SwiftDiskArbitration] Eject completed: eject took \(String(format: "%.4f", ejectElapsed))s, total=\(String(format: "%.4f", totalDuration))s")
    }

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
    // PRIVACY: Use BSD name only, not user-visible volume name
    print("[SwiftDiskArbitration] Using DADiskUnmount for \(volume.info.bsdName ?? "?")")
  }

  let unmountResult = await unmountDiskAsync(
    volume.disk,
    options: DADiskUnmountOptions(unmountOptions)
  )

  return unmountResult
}
