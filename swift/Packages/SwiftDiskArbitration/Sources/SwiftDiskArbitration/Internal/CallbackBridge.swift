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
// 3. WHY THE TIMEOUT IS A "RESUME-ONCE" RACE (not a task group)
//    DADiskUnmount/DADiskEject have no cancellation API. If a drive wedges
//    and the callback never fires, nothing can interrupt it. A structured
//    task group cannot express this: `withTaskGroup` implicitly awaits all
//    of its children before returning, so a child parked on a continuation
//    that never resumes would hang the group forever — even after the
//    timeout child "won".
//
//    Instead, both the DA callback and a detached timeout task race to
//    resume ONE continuation. DiskCallbackContext guarantees exactly one
//    of them wins; the loser's result is dropped.
//
// MEMORY SAFETY FLOW:
// -------------------
//   1. Create context object holding the continuation
//   2. passRetained() → keeps object alive, gives us void*
//   3. Pass void* to C function (DADiskUnmount/DADiskEject)
//   4. C calls our callback with the void*
//   5. takeRetainedValue() → gets object back, balances retain
//   6. Resume continuation (unless the timeout already did) → Swift continues
//
//   If the DA callback NEVER fires, the timeout resumes the continuation and
//   the retained context object leaks (one small allocation). That is an
//   accepted trade-off versus hanging the eject operation forever.
//
// ============================================================================

import DiskArbitration
import Foundation

// MARK: - Timeout Configuration

/// Overall time budget for ejecting one physical device (unmount + eject).
/// This prevents the plugin from hanging indefinitely if a drive is unresponsive.
internal let diskOperationTimeoutSeconds: TimeInterval = 30.0

/// Minimum budget any single stage (unmount or eject) is allowed, so a slow
/// unmount cannot leave the eject stage with a zero/negative timeout.
internal let minimumStageTimeoutSeconds: TimeInterval = 5.0

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

/// Context object that holds the continuation for async bridging and
/// guarantees it is resumed exactly once, no matter whether the DA callback
/// or the timeout watchdog gets there first.
internal final class DiskCallbackContext: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<DiskOperationResult, Never>?
  let startTime = Date()

  init(continuation: CheckedContinuation<DiskOperationResult, Never>) {
    self.continuation = continuation
  }

  /// Resumes the continuation with `result` if it has not been resumed yet.
  /// - Returns: true if this call performed the resume, false if it lost the race.
  @discardableResult
  func resume(with result: DiskOperationResult) -> Bool {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()

    guard let continuation else { return false }
    continuation.resume(returning: result)
    return true
  }
}

// MARK: - C Callback Functions

/// Enable debug output for troubleshooting
/// Set to false in production to reduce console noise
internal let debugCallbacks = false

/// Shared handler for both DA callbacks: converts the dissenter into a result
/// and resumes the continuation (unless the timeout already resumed it).
private func resumeDiskCallback(context: UnsafeMutableRawPointer?, dissenter: DADissenter?) {
  guard let context else {
    // This should never happen if we set up the call correctly
    if debugCallbacks {
      print("[SwiftDiskArbitration] ERROR: disk callback received nil context!")
    }
    return
  }

  // Retrieve and release the context object (balances passRetained)
  let ctx = Unmanaged<DiskCallbackContext>.fromOpaque(context).takeRetainedValue()
  let duration = Date().timeIntervalSince(ctx.startTime)

  if debugCallbacks {
    if let dissenter = dissenter {
      let status = DADissenterGetStatus(dissenter)
      print(
        "[SwiftDiskArbitration] disk callback: dissenter status=0x\(String(status, radix: 16)), duration=\(String(format: "%.4f", duration))s"
      )
    } else {
      print("[SwiftDiskArbitration] disk callback: success, duration=\(String(format: "%.4f", duration))s")
    }
  }

  let result: DiskOperationResult
  if let error = DiskError.from(dissenter: dissenter) {
    result = DiskOperationResult(success: false, error: error, duration: duration)
  } else {
    result = DiskOperationResult(success: true, error: nil, duration: duration)
  }

  // Dropped silently if the timeout watchdog already resumed the continuation.
  ctx.resume(with: result)
}

/// C callback for DADiskUnmount
/// This function has @convention(c) semantics and cannot capture Swift context directly
internal let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
  resumeDiskCallback(context: context, dissenter: dissenter)
}

/// C callback for DADiskEject
internal let ejectCallback: DADiskEjectCallback = { _, dissenter, context in
  resumeDiskCallback(context: context, dissenter: dissenter)
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
///   - timeout: Maximum time to wait for the operation
/// - Returns: Result of the unmount operation
nonisolated internal func unmountDiskAsync(
  _ disk: DADisk,
  options: DADiskUnmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionDefault),
  timeout: TimeInterval = diskOperationTimeoutSeconds
) async -> DiskOperationResult {
  await withCheckedContinuation { continuation in
    let context = DiskCallbackContext(continuation: continuation)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()

    // Timeout watchdog: races the DA callback to resume the continuation.
    Task {
      try? await Task.sleep(for: .seconds(timeout))
      context.resume(
        with: DiskOperationResult(success: false, error: .timeout, duration: timeout)
      )
    }

    DADiskUnmount(disk, options, unmountCallback, contextPtr)
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
///   - timeout: Maximum time to wait for the operation
/// - Returns: Result of the eject operation
nonisolated internal func ejectDiskAsync(
  _ disk: DADisk,
  options: DADiskEjectOptions = DADiskEjectOptions(kDADiskEjectOptionDefault),
  timeout: TimeInterval = diskOperationTimeoutSeconds
) async -> DiskOperationResult {
  await withCheckedContinuation { continuation in
    let context = DiskCallbackContext(continuation: continuation)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()

    // Timeout watchdog: races the DA callback to resume the continuation.
    Task {
      try? await Task.sleep(for: .seconds(timeout))
      context.resume(
        with: DiskOperationResult(success: false, error: .timeout, duration: timeout)
      )
    }

    DADiskEject(disk, options, ejectCallback, contextPtr)
  }
}

// MARK: - Combined Operations

/// Unmounts every volume on a whole disk, then ejects the physical device,
/// all within a single overall time budget.
///
/// Both `DiskSession.ejectAll` (batch path) and `unmountAndEjectAsync`
/// (single-volume path) funnel through this helper so the two-step flow
/// exists in exactly one place.
///
/// - Parameters:
///   - wholeDisk: The whole-disk DADisk reference (physical device)
///   - force: Whether to force unmount even if files are open
///   - budget: Overall deadline for unmount + eject combined
/// - Returns: Result of the combined operation
nonisolated internal func unmountWholeDiskAndEject(
  _ wholeDisk: DADisk,
  force: Bool,
  budget: TimeInterval = diskOperationTimeoutSeconds
) async -> DiskOperationResult {
  let startTime = Date()

  // Step 1: Unmount all volumes on the whole disk
  var unmountOptions = kDADiskUnmountOptionWhole
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  let unmountResult = await unmountDiskAsync(
    wholeDisk,
    options: DADiskUnmountOptions(unmountOptions),
    timeout: budget
  )

  guard unmountResult.success else {
    if debugCallbacks {
      print("[SwiftDiskArbitration] Unmount failed: \(unmountResult.error?.description ?? "unknown")")
    }
    return unmountResult
  }

  // Step 2: Eject the physical device with whatever budget remains
  let remaining = max(minimumStageTimeoutSeconds, budget - Date().timeIntervalSince(startTime))
  let ejectResult = await ejectDiskAsync(wholeDisk, timeout: remaining)
  let totalDuration = Date().timeIntervalSince(startTime)

  return DiskOperationResult(
    success: ejectResult.success,
    error: ejectResult.error,
    duration: totalDuration
  )
}

/// Unmounts and optionally ejects a volume.
///
/// For external drives, unmounts the whole disk then ejects the physical
/// device. This is more reliable than DADiskUnmount alone for removable media.
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
  // For ejection of external drives, unmount all volumes on the whole disk
  // first, then eject the physical device — one shared code path.
  if ejectAfterUnmount, let wholeDisk = volume.wholeDisk {
    return await unmountWholeDiskAndEject(wholeDisk, force: force)
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

  return await unmountDiskAsync(
    volume.disk,
    options: DADiskUnmountOptions(unmountOptions)
  )
}
