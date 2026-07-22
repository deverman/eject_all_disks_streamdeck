//
//  CallbackBridge.swift
//  SwiftDiskArbitration
//
//  Converts DiskArbitration callbacks to async results with absolute monotonic
//  deadlines. A process-local token registry arbitrates callback, timeout, and
//  cancellation without exposing retained Swift objects to C.
//

import DiskArbitration
import Foundation
import Synchronization

/// Result of an unmount or eject operation.
public struct DiskOperationResult: Sendable {
  public let success: Bool
  public let error: DiskError?
  public let duration: TimeInterval

  /// Stage that produced this result. Older callers can continue using the
  /// original fields without inspecting this value.
  public let stage: DiskOperationStage?

  /// Raw DiskArbitration status for future diagnostics, when available.
  public let rawStatus: DAReturn?

  internal init(
    success: Bool,
    error: DiskError?,
    duration: TimeInterval,
    stage: DiskOperationStage? = nil,
    rawStatus: DAReturn? = nil
  ) {
    self.success = success
    self.error = error
    self.duration = duration
    self.stage = stage
    self.rawStatus = rawStatus
  }
}

// MARK: - Single-stage bridge

private enum DiskSubmission {
  case unmount(DADisk, DADiskUnmountOptions)
  case eject(DADisk, DADiskEjectOptions)

  func submit(token: UInt) {
    switch self {
    case .unmount(let disk, let options):
      DiskArbitrationUnsafeAdapter.submitUnmount(disk, options: options, token: token)
    case .eject(let disk, let options):
      DiskArbitrationUnsafeAdapter.submitEject(disk, options: options, token: token)
    }
  }
}

private func performDiskOperation<C: Clock>(
  submission: DiskSubmission,
  stage: DiskOperationStage,
  startedAt: C.Instant,
  deadline: C.Instant,
  clock: C,
  registry: DiskOperationRegistry = .shared
) async -> DiskOperationResult where C.Duration == Duration {
  await performRegisteredDiskOperation(
    stage: stage,
    startedAt: startedAt,
    deadline: deadline,
    clock: clock,
    registry: registry,
    submit: { token in submission.submit(token: token) }
  )
}

/// Clock- and submission-injectable core used by deterministic deadline tests.
/// Production passes the synchronous DiskArbitration submit call; tests pass a
/// controlled callback/never-callback closure without manufacturing a DADisk.
nonisolated internal func performRegisteredDiskOperation<C: Clock>(
  stage: DiskOperationStage,
  startedAt: C.Instant,
  deadline: C.Instant,
  clock: C,
  registry: DiskOperationRegistry,
  submit: @escaping (UInt) -> Void
) async -> DiskOperationResult where C.Duration == Duration {
  let elapsed: @Sendable () -> TimeInterval = {
    startedAt.duration(to: clock.now).diskOperationTimeInterval
  }

  guard clock.now < deadline else {
    return DiskOperationResult(
      success: false,
      error: .timeout,
      duration: elapsed(),
      stage: stage
    )
  }

  let tokenStorage = Mutex<UInt?>(nil)

  return await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
      guard !Task.isCancelled else {
        continuation.resume(
          returning: DiskOperationResult(
            success: false,
            error: .cancelled,
            duration: elapsed(),
            stage: stage
          )
        )
        return
      }

      let token = registry.register(
        continuation: continuation,
        stage: stage,
        elapsed: elapsed
      )
      tokenStorage.withLock { $0 = token }

      guard !Task.isCancelled else {
        registry.completeAsCancelled(token: token)
        return
      }

      let watchdog = Task { @concurrent in
        do {
          try await clock.sleep(until: deadline, tolerance: nil)
        } catch {
          return
        }

        guard !Task.isCancelled else { return }
        registry.completeAsTimeout(token: token)
      }
      registry.installWatchdog(watchdog, for: token)

      // This is the cancellation/submission linearization point. A cancellation
      // that removed the token first prevents the C call from being issued.
      guard registry.commitSubmission(for: token) else { return }
      submit(token)
    }
  } onCancel: {
    guard let token = tokenStorage.withLock({ $0 }) else { return }
    registry.completeAsCancelled(token: token)
  }
}

nonisolated internal func unmountDiskAsync(
  _ disk: DADisk,
  options: DADiskUnmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionDefault),
  deadline: ContinuousClock.Instant,
  startedAt: ContinuousClock.Instant,
  clock: ContinuousClock = ContinuousClock()
) async -> DiskOperationResult {
  await performDiskOperation(
    submission: .unmount(disk, options),
    stage: .unmount,
    startedAt: startedAt,
    deadline: deadline,
    clock: clock
  )
}

nonisolated internal func ejectDiskAsync(
  _ disk: DADisk,
  options: DADiskEjectOptions = DADiskEjectOptions(kDADiskEjectOptionDefault),
  deadline: ContinuousClock.Instant,
  startedAt: ContinuousClock.Instant,
  clock: ContinuousClock = ContinuousClock()
) async -> DiskOperationResult {
  await performDiskOperation(
    submission: .eject(disk, options),
    stage: .eject,
    startedAt: startedAt,
    deadline: deadline,
    clock: clock
  )
}

nonisolated internal func unmountDiskAsync(
  _ disk: DADisk,
  options: DADiskUnmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionDefault)
) async -> DiskOperationResult {
  let clock = ContinuousClock()
  let startedAt = clock.now
  return await unmountDiskAsync(
    disk,
    options: options,
    deadline: startedAt.advanced(by: diskOperationTimeout),
    startedAt: startedAt,
    clock: clock
  )
}

nonisolated internal func ejectDiskAsync(
  _ disk: DADisk,
  options: DADiskEjectOptions = DADiskEjectOptions(kDADiskEjectOptionDefault)
) async -> DiskOperationResult {
  let clock = ContinuousClock()
  let startedAt = clock.now
  return await ejectDiskAsync(
    disk,
    options: options,
    deadline: startedAt.advanced(by: diskOperationTimeout),
    startedAt: startedAt,
    clock: clock
  )
}

// MARK: - Combined whole-device operation

nonisolated internal func unmountWholeDiskAndEject(
  _ wholeDisk: DADisk,
  force: Bool,
  deviceID: PhysicalDeviceID? = nil,
  onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void = { _ in }
) async -> DiskOperationResult {
  let clock = ContinuousClock()
  let startedAt = clock.now
  let deadlines = DeviceOperationDeadlines<ContinuousClock>(startedAt: startedAt)

  var unmountOptions = kDADiskUnmountOptionWhole
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  if let deviceID {
    await onProgress(.unmountStarted(deviceID))
  }

  let unmountResult = await unmountDiskAsync(
    wholeDisk,
    options: DADiskUnmountOptions(unmountOptions),
    deadline: deadlines.unmountDeadline,
    startedAt: startedAt,
    clock: clock
  )

  guard unmountResult.success else {
    if let deviceID {
      await onProgress(.completed(deviceID, outcome(for: unmountResult, deviceID: deviceID)))
    }
    return unmountResult
  }

  if let deviceID {
    await onProgress(.unmountCompleted(deviceID))
    await onProgress(.ejectStarted(deviceID))
  }

  let ejectResult = await ejectDiskAsync(
    wholeDisk,
    deadline: deadlines.overallDeadline,
    startedAt: startedAt,
    clock: clock
  )

  let combined = DiskOperationResult(
    success: ejectResult.success,
    error: ejectResult.error,
    duration: startedAt.duration(to: clock.now).diskOperationTimeInterval,
    stage: ejectResult.stage,
    rawStatus: ejectResult.rawStatus
  )

  if let deviceID {
    await onProgress(.completed(deviceID, outcome(for: combined, deviceID: deviceID)))
  }
  return combined
}

private func outcome(
  for result: DiskOperationResult,
  deviceID: PhysicalDeviceID
) -> DeviceEjectOutcome {
  let stage = result.stage ?? .unmount

  if result.success {
    return stage == .eject
      ? .safeToRemove(duration: result.duration)
      : .unmounted(duration: result.duration)
  }

  switch result.error?.category {
  case .timeout:
    return .timedOut(stage: stage, duration: result.duration)
  case .cancelled:
    return .cancelled(stage: stage, duration: result.duration)
  case .some(let category):
    return .failed(
      DeviceEjectFailure(
        deviceID: deviceID,
        stage: stage,
        category: category,
        rawStatus: result.rawStatus
      ),
      duration: result.duration
    )
  case .none:
    return .failed(
      DeviceEjectFailure(
        deviceID: deviceID,
        stage: stage,
        category: .other,
        rawStatus: result.rawStatus
      ),
      duration: result.duration
    )
  }
}

nonisolated internal func unmountAndEjectAsync(
  _ volume: Volume,
  ejectAfterUnmount: Bool,
  force: Bool
) async -> DiskOperationResult {
  if ejectAfterUnmount, let wholeDisk = volume.wholeDisk {
    return await unmountWholeDiskAndEject(wholeDisk, force: force)
  }

  var unmountOptions = kDADiskUnmountOptionDefault
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  return await unmountDiskAsync(
    volume.disk,
    options: DADiskUnmountOptions(unmountOptions)
  )
}
