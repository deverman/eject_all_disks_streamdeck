import Foundation
import Synchronization
import Testing

@testable import SwiftDiskArbitration

@Suite("Monotonic disk operation timing")
struct DiskOperationTimingTests {
  @Test("Combined operation uses absolute 25 and 30 second deadlines")
  func standardDeadlines() {
    let start = ManualInstant(offset: .seconds(100))
    let deadlines = DeviceOperationDeadlines<ManualClock>(startedAt: start)

    #expect(start.duration(to: deadlines.unmountDeadline) == .seconds(25))
    #expect(start.duration(to: deadlines.overallDeadline) == .seconds(30))
  }

  @Test("Unmount deadline can never exceed the overall deadline")
  func shortOverallBudget() {
    let start = ManualInstant(offset: .zero)
    let deadlines = DeviceOperationDeadlines<ManualClock>(
      startedAt: start,
      unmountTimeout: .seconds(25),
      overallTimeout: .seconds(10)
    )

    #expect(deadlines.unmountDeadline == deadlines.overallDeadline)
    #expect(start.duration(to: deadlines.overallDeadline) == .seconds(10))
  }

  @Test("Eject receives only the original remaining budget", arguments: [
    (2, 28),
    (24, 6),
    (25, 5),
  ])
  func remainingEjectBudget(unmountSeconds: Int, expectedSeconds: Int) {
    let start = ManualInstant(offset: .zero)
    let deadlines = DeviceOperationDeadlines<ManualClock>(startedAt: start)
    let unmountFinished = start.advanced(by: .seconds(unmountSeconds))

    #expect(unmountFinished.duration(to: deadlines.overallDeadline) == .seconds(expectedSeconds))
  }

  @Test("Duration conversion preserves monotonic fractions")
  func timeIntervalConversion() {
    #expect(Duration.seconds(2.5).diskOperationTimeInterval == 2.5)
    #expect(Duration.seconds(-1).diskOperationTimeInterval == 0)
  }

  @Test("Standalone operations retain one absolute 30 second budget")
  func standaloneBudget() {
    #expect(diskOperationTimeout == .seconds(30))
  }

  @Test("Definitive dissenters return immediately at their monotonic callback time", arguments: [
    DiskError.busy(message: nil),
    DiskError.notPermitted(message: nil),
  ])
  func immediateDissenter(error: DiskError) async {
    let storage = ManualClockStorage()
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    let start = clock.now

    let result = await performRegisteredDiskOperation(
      stage: .unmount,
      startedAt: start,
      deadline: start.advanced(by: .seconds(25)),
      clock: clock,
      registry: registry
    ) { token in
      storage.advance(by: .milliseconds(100))
      #expect(registry.completeFromCallback(token: token, error: error, rawStatus: nil))
    }

    #expect(result.error?.category == error.category)
    #expect(result.duration == 0.1)
    #expect(registry.pendingCount == 0)
  }

  @Test("Unmount watchdog wins at its exact 25 second deadline")
  func unmountDeadlineWins() async throws {
    let storage = ManualClockStorage()
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    let start = clock.now
    var registrations = storage.sleepRegistrations.makeAsyncIterator()

    let operation = Task {
      await performRegisteredDiskOperation(
        stage: .unmount,
        startedAt: start,
        deadline: start.advanced(by: .seconds(25)),
        clock: clock,
        registry: registry,
        submit: { _ in }
      )
    }

    _ = try #require(await registrations.next())
    storage.advance(to: start.advanced(by: .seconds(25)))
    let result = await operation.value
    #expect(result.error?.category == .timeout)
    #expect(result.stage == .unmount)
    #expect(result.duration == 25)
    #expect(registry.pendingCount == 0)
  }

  @Test("Eject watchdog uses the original absolute 30 second deadline")
  func overallDeadlineWins() async throws {
    let start = ManualInstant(offset: .zero)
    let storage = ManualClockStorage(now: start.advanced(by: .seconds(24)))
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    var registrations = storage.sleepRegistrations.makeAsyncIterator()

    let operation = Task {
      await performRegisteredDiskOperation(
        stage: .eject,
        startedAt: start,
        deadline: start.advanced(by: .seconds(30)),
        clock: clock,
        registry: registry,
        submit: { _ in }
      )
    }

    _ = try #require(await registrations.next())
    storage.advance(to: start.advanced(by: .seconds(30)))
    let result = await operation.value
    #expect(result.error?.category == .timeout)
    #expect(result.stage == .eject)
    #expect(result.duration == 30)
  }

  @Test("Callback wins an exact deadline race when ordered first")
  func callbackWinsExactRace() async {
    let storage = ManualClockStorage()
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    let start = clock.now
    let deadline = start.advanced(by: .seconds(25))

    let result = await performRegisteredDiskOperation(
      stage: .unmount,
      startedAt: start,
      deadline: deadline,
      clock: clock,
      registry: registry
    ) { token in
      storage.advance(to: deadline)
      #expect(registry.completeFromCallback(token: token, error: nil, rawStatus: nil))
    }

    #expect(result.success)
    #expect(result.duration == 25)
    #expect(registry.pendingCount == 0)
  }

  @Test("Deadline wins an exact race when ordered before a late callback")
  func deadlineWinsExactRace() async throws {
    let storage = ManualClockStorage()
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    let token = Mutex<UInt?>(nil)
    let start = clock.now
    let deadline = start.advanced(by: .seconds(25))
    var registrations = storage.sleepRegistrations.makeAsyncIterator()

    let operation = Task {
      await performRegisteredDiskOperation(
        stage: .unmount,
        startedAt: start,
        deadline: deadline,
        clock: clock,
        registry: registry
      ) { registeredToken in
        token.withLock { $0 = registeredToken }
      }
    }

    _ = try #require(await registrations.next())
    storage.advance(to: deadline)
    let result = await operation.value
    let registeredToken = try #require(token.withLock { $0 })
    #expect(!registry.completeFromCallback(token: registeredToken, error: nil, rawStatus: nil))
    #expect(result.error?.category == .timeout)
    #expect(registry.pendingCount == 0)
  }

  @Test("An already-expired deadline never submits the C operation")
  func expiredDeadlineSkipsSubmission() async {
    let storage = ManualClockStorage(now: ManualInstant(offset: .seconds(10)))
    let clock = ManualClock(storage: storage)
    let registry = DiskOperationRegistry()
    let submitted = Mutex(false)
    let start = ManualInstant(offset: .zero)

    let result = await performRegisteredDiskOperation(
      stage: .eject,
      startedAt: start,
      deadline: ManualInstant(offset: .seconds(10)),
      clock: clock,
      registry: registry
    ) { _ in
      submitted.withLock { $0 = true }
    }

    #expect(result.error?.category == .timeout)
    #expect(!submitted.withLock { $0 })
    #expect(registry.pendingCount == 0)
  }
}

private struct ManualInstant: InstantProtocol, Hashable, Sendable {
  let offset: Duration

  func advanced(by duration: Duration) -> Self {
    Self(offset: offset + duration)
  }

  func duration(to other: Self) -> Duration {
    other.offset - offset
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.offset < rhs.offset
  }
}

private struct ManualClock: Clock, Sendable {
  typealias Instant = ManualInstant
  typealias Duration = Swift.Duration

  let storage: ManualClockStorage

  init(storage: ManualClockStorage = ManualClockStorage()) {
    self.storage = storage
  }

  var now: ManualInstant { storage.now }
  let minimumResolution: Duration = .nanoseconds(1)

  func sleep(until deadline: ManualInstant, tolerance: Duration?) async throws {
    try await storage.sleep(until: deadline)
  }
}

private final class ManualClockStorage: Sendable {
  private struct Sleeper: Sendable {
    let deadline: ManualInstant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private struct State: Sendable {
    var now: ManualInstant
    var sleepers: [UUID: Sleeper] = [:]
    var cancelledBeforeRegistration: Set<UUID> = []
  }

  private let state: Mutex<State>
  private let registrationContinuation: AsyncStream<Void>.Continuation
  let sleepRegistrations: AsyncStream<Void>

  init(now: ManualInstant = ManualInstant(offset: .zero)) {
    let registrations = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
    self.sleepRegistrations = registrations.stream
    self.registrationContinuation = registrations.continuation
    self.state = Mutex(State(now: now))
  }

  var now: ManualInstant { state.withLock { $0.now } }

  func sleep(until deadline: ManualInstant) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let disposition: SleepDisposition = state.withLock { state in
          if state.cancelledBeforeRegistration.remove(id) != nil || Task.isCancelled {
            return .cancelled
          }
          if state.now >= deadline {
            return .ready
          }
          state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
          return .waiting
        }

        switch disposition {
        case .ready:
          continuation.resume()
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        case .waiting:
          registrationContinuation.yield()
        }
      }
    } onCancel: {
      let sleeper: Sleeper? = state.withLock { state in
        if let sleeper = state.sleepers.removeValue(forKey: id) {
          return sleeper
        }
        state.cancelledBeforeRegistration.insert(id)
        return nil
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  func advance(by duration: Duration) {
    advance(to: now.advanced(by: duration))
  }

  func advance(to instant: ManualInstant) {
    let due: [Sleeper] = state.withLock { state in
      precondition(instant >= state.now, "Manual clock cannot move backwards")
      state.now = instant
      let dueIDs = state.sleepers.compactMap { id, sleeper in
        sleeper.deadline <= instant ? id : nil
      }
      return dueIDs.compactMap { state.sleepers.removeValue(forKey: $0) }
    }
    for sleeper in due {
      sleeper.continuation.resume()
    }
  }

  private enum SleepDisposition: Sendable {
    case ready
    case cancelled
    case waiting
  }
}
