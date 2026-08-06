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
import OSLog
import Synchronization

internal let diskOperationLog = Logger(
  subsystem: "org.deverman.ejectalldisks",
  category: "disk-operation"
)

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
  guard
    let bsdName = DiskArbitrationUnsafeAdapter.bsdName(of: wholeDisk),
    let topology = ResolvedDiskTopology(
      layers: [ResolvedDiskLayer(disk: wholeDisk, bsdName: bsdName)]
    )
  else {
    return DiskOperationResult(
      success: false,
      error: .invalidDiskReference,
      duration: 0,
      stage: .unmount
    )
  }

  return await unmountResolvedDiskStackAndEject(
    topology,
    force: force,
    deviceID: deviceID,
    onProgress: onProgress
  )
}

/// Unmounts the innermost whole media, then ejects every whole-media layer
/// from inner to outer. APFS commonly requires `disk7` before physical `disk6`.
///
/// Every stage shares one absolute monotonic 30-second deadline. Completing an
/// intermediate virtual eject never produces `safeToRemove`; only confirmation
/// from the outermost physical layer does.
nonisolated internal func unmountResolvedDiskStackAndEject(
  _ topology: ResolvedDiskTopology,
  force: Bool,
  deviceID: PhysicalDeviceID? = nil,
  onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void = { _ in }
) async -> DiskOperationResult {
  guard let deviceTopology = ResolvedDeviceEjectTopology(topologies: [topology]) else {
    return DiskOperationResult(
      success: false,
      error: .invalidDiskReference,
      duration: 0,
      stage: .unmount
    )
  }

  return await unmountResolvedDeviceTopologyAndEject(
    deviceTopology,
    force: force,
    deviceID: deviceID,
    onProgress: onProgress
  )
}

nonisolated internal func unmountResolvedDeviceTopologyAndEject(
  _ topology: ResolvedDeviceEjectTopology,
  force: Bool,
  deviceID: PhysicalDeviceID? = nil,
  onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void = { _ in }
) async -> DiskOperationResult {
  let clock = ContinuousClock()
  let startedAt = clock.now
  let deadlines = DeviceOperationDeadlines<ContinuousClock>(startedAt: startedAt)
  let plan = DiskEjectPlan(
    unmountBSDNames: topology.unmountLayers.map(\.bsdName),
    ejectBSDNames: topology.ejectLayers.map(\.bsdName)
  )

  guard
    let plan,
    plan.unmountBSDNames.count == topology.unmountLayers.count,
    plan.ejectBSDNames.count == topology.ejectLayers.count
  else {
    return DiskOperationResult(
      success: false,
      error: .invalidDiskReference,
      duration: 0,
      stage: .unmount
    )
  }

  var unmountOptions = kDADiskUnmountOptionWhole
  if force {
    unmountOptions |= kDADiskUnmountOptionForce
  }

  if let deviceID {
    await onProgress(.unmountStarted(deviceID))
  }

  diskOperationLog.info(
    "operation=start device=\(plan.physicalBSDName, privacy: .public) unmountTargets=\(plan.unmountBSDNames.joined(separator: ","), privacy: .public) ejectLayers=\(plan.ejectBSDNames.joined(separator: ","), privacy: .public)"
  )

  for layer in topology.unmountLayers {
    diskOperationLog.info(
      "stage=unmount event=submit device=\(plan.physicalBSDName, privacy: .public) target=\(layer.bsdName, privacy: .public)"
    )
    let unmountResult = await unmountDiskAsync(
      layer.disk,
      options: DADiskUnmountOptions(unmountOptions),
      deadline: deadlines.unmountDeadline,
      startedAt: startedAt,
      clock: clock
    )
    logDiskStageResult(
      unmountResult,
      deviceBSDName: plan.physicalBSDName,
      targetBSDName: layer.bsdName
    )

    guard unmountResult.success else {
      if let deviceID {
        await onProgress(.completed(deviceID, outcome(for: unmountResult, deviceID: deviceID)))
      }
      return unmountResult
    }
  }

  if let deviceID {
    await onProgress(.unmountCompleted(deviceID))
    await onProgress(.ejectStarted(deviceID))
  }

  var lastEjectResult: DiskOperationResult?
  for layer in topology.ejectLayers {
    diskOperationLog.info(
      "stage=eject event=submit device=\(plan.physicalBSDName, privacy: .public) target=\(layer.bsdName, privacy: .public)"
    )
    let ejectResult = await ejectDiskAsync(
      layer.disk,
      deadline: deadlines.overallDeadline,
      startedAt: startedAt,
      clock: clock
    )
    logDiskStageResult(
      ejectResult,
      deviceBSDName: plan.physicalBSDName,
      targetBSDName: layer.bsdName
    )
    lastEjectResult = ejectResult

    guard ejectResult.success else {
      if let deviceID {
        await onProgress(.completed(deviceID, outcome(for: ejectResult, deviceID: deviceID)))
      }
      return ejectResult
    }
  }

  guard let lastEjectResult else {
    return DiskOperationResult(
      success: false,
      error: .invalidDiskReference,
      duration: startedAt.duration(to: clock.now).diskOperationTimeInterval,
      stage: .eject
    )
  }

  let combined = DiskOperationResult(
    success: true,
    error: nil,
    duration: startedAt.duration(to: clock.now).diskOperationTimeInterval,
    stage: .eject,
    rawStatus: lastEjectResult.rawStatus
  )

  diskOperationLog.notice(
    "operation=complete device=\(plan.physicalBSDName, privacy: .public) result=success category=none rawStatus=\(diskStatusDescription(combined.rawStatus), privacy: .public) durationSeconds=\(combined.duration, privacy: .public) ejectLayers=\(plan.ejectBSDNames.joined(separator: ","), privacy: .public)"
  )

  if let deviceID {
    await onProgress(.completed(deviceID, outcome(for: combined, deviceID: deviceID)))
  }
  return combined
}

private nonisolated func logDiskStageResult(
  _ result: DiskOperationResult,
  deviceBSDName: String,
  targetBSDName: String
) {
  let resultName = result.success ? "success" : "failure"
  let category = result.error?.category.rawValue ?? "none"
  let rawStatus = diskStatusDescription(result.rawStatus)
  let stage = result.stage?.rawValue ?? "unknown"

  if result.success {
    diskOperationLog.info(
      "stage=\(stage, privacy: .public) event=complete device=\(deviceBSDName, privacy: .public) target=\(targetBSDName, privacy: .public) result=\(resultName, privacy: .public) category=\(category, privacy: .public) rawStatus=\(rawStatus, privacy: .public) durationSeconds=\(result.duration, privacy: .public)"
    )
  } else {
    diskOperationLog.error(
      "operation=complete stage=\(stage, privacy: .public) device=\(deviceBSDName, privacy: .public) target=\(targetBSDName, privacy: .public) result=\(resultName, privacy: .public) category=\(category, privacy: .public) rawStatus=\(rawStatus, privacy: .public) durationSeconds=\(result.duration, privacy: .public)"
    )
  }
}

private nonisolated func diskStatusDescription(_ status: DAReturn?) -> String {
  guard let status else { return "none" }
  let hex = String(UInt32(bitPattern: status), radix: 16, uppercase: true)
  return "0x" + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
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
