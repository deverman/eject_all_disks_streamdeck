//
//  DiskOperationRegistry.swift
//  SwiftDiskArbitration
//
//  Exactly-once completion arbitration for DiskArbitration callbacks,
//  watchdog deadlines, and Swift task cancellation.
//

import DiskArbitration
import Foundation
import Synchronization

/// Process-local registry whose integer tokens are passed through C as opaque
/// cookies. No Swift object address is ever exposed to DiskArbitration.
internal final class DiskOperationRegistry: Sendable {
  internal static let shared = DiskOperationRegistry()

  private struct Pending: Sendable {
    let continuation: CheckedContinuation<DiskOperationResult, Never>
    let stage: DiskOperationStage
    let elapsed: @Sendable () -> TimeInterval
    var watchdog: Task<Void, Never>?
  }

  private struct State: Sendable {
    var nextToken: UInt
    var pending: [UInt: Pending] = [:]
  }

  private let state: Mutex<State>

  internal init(startingToken: UInt = 1) {
    state = Mutex(State(nextToken: startingToken == 0 ? 1 : startingToken))
  }

  /// Allocates a nonzero token and records its continuation.
  internal func register(
    continuation: CheckedContinuation<DiskOperationResult, Never>,
    stage: DiskOperationStage,
    elapsed: @escaping @Sendable () -> TimeInterval
  ) -> UInt {
    state.withLock { state in
      let firstCandidate = state.nextToken == 0 ? 1 : state.nextToken
      var candidate = firstCandidate

      while state.pending[candidate] != nil {
        candidate &+= 1
        if candidate == 0 { candidate = 1 }
        precondition(candidate != firstCandidate, "Disk operation token space exhausted")
      }

      var next = candidate &+ 1
      if next == 0 { next = 1 }
      state.nextToken = next
      state.pending[candidate] = Pending(
        continuation: continuation,
        stage: stage,
        elapsed: elapsed
      )
      return candidate
    }
  }

  /// Gives the registry ownership of the watchdog task. If another completion
  /// already won, the newly created watchdog is cancelled immediately.
  internal func installWatchdog(_ watchdog: Task<Void, Never>, for token: UInt) {
    let installed = state.withLock { state in
      guard var pending = state.pending[token] else { return false }
      pending.watchdog = watchdog
      state.pending[token] = pending
      return true
    }

    if !installed {
      watchdog.cancel()
    }
  }

  /// Linearization point for submitting the C operation. Cancellation that won
  /// before this point prevents submission; cancellation after it cannot cancel
  /// DiskArbitration and is treated as a caller-side completion only.
  internal func commitSubmission(for token: UInt) -> Bool {
    state.withLock { $0.pending[token] != nil }
  }

  @discardableResult
  internal func completeFromCallback(
    token: UInt,
    error: DiskError?,
    rawStatus: DAReturn?
  ) -> Bool {
    complete(token: token) { pending in
      DiskOperationResult(
        success: error == nil,
        error: error,
        duration: pending.elapsed(),
        stage: pending.stage,
        rawStatus: rawStatus
      )
    }
  }

  @discardableResult
  internal func completeAsTimeout(token: UInt) -> Bool {
    complete(token: token) { pending in
      DiskOperationResult(
        success: false,
        error: .timeout,
        duration: pending.elapsed(),
        stage: pending.stage,
        rawStatus: nil
      )
    }
  }

  @discardableResult
  internal func completeAsCancelled(token: UInt) -> Bool {
    complete(token: token) { pending in
      DiskOperationResult(
        success: false,
        error: .cancelled,
        duration: pending.elapsed(),
        stage: pending.stage,
        rawStatus: nil
      )
    }
  }

  /// Removes under the mutex, then cancels/resumes outside it. The result
  /// factory also runs outside the critical section so re-entrant test hooks
  /// and continuations can never deadlock the registry.
  private func complete(
    token: UInt,
    makeResult: (Pending) -> DiskOperationResult
  ) -> Bool {
    guard let pending = state.withLock({ state in
      state.pending.removeValue(forKey: token)
    }) else {
      return false
    }

    pending.watchdog?.cancel()
    let result = makeResult(pending)
    pending.continuation.resume(returning: result)
    return true
  }

  internal var pendingCount: Int {
    state.withLock { $0.pending.count }
  }

  internal func contains(token: UInt) -> Bool {
    state.withLock { $0.pending[token] != nil }
  }
}
