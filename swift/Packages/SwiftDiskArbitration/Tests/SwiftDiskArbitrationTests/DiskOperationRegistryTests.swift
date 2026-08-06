import DiskArbitration
import Synchronization
import Testing

@testable import SwiftDiskArbitration

@Suite("Disk operation registry", .tags(.concurrency))
struct DiskOperationRegistryTests {
  @Test("Callback, timeout, and cancellation each win exactly once", arguments: [
    Completion.callback, .timeout, .cancelled,
  ])
  func terminalCompletion(_ completion: Completion) async {
    let registry = DiskOperationRegistry()
    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let token = registry.register(
        continuation: continuation,
        stage: .unmount,
        elapsed: { 0.25 }
      )

      switch completion {
      case .callback:
        #expect(registry.completeFromCallback(token: token, error: nil, rawStatus: nil))
      case .timeout:
        #expect(registry.completeAsTimeout(token: token))
      case .cancelled:
        #expect(registry.completeAsCancelled(token: token))
      }

      #expect(!registry.completeAsTimeout(token: token))
      #expect(!registry.completeAsCancelled(token: token))
      #expect(!registry.completeFromCallback(token: token, error: nil, rawStatus: nil))
    }

    switch completion {
    case .callback:
      #expect(result.success)
    case .timeout:
      #expect(result.error?.category == .timeout)
    case .cancelled:
      #expect(result.error?.category == .cancelled)
    }
    #expect(registry.pendingCount == 0)
  }

  @Test("Concurrent terminal races leave no pending entry", arguments: 0..<500)
  func concurrentTerminalRace(iteration: Int) async {
    let registry = DiskOperationRegistry(startingToken: UInt(iteration + 1))
    let winnerCount = WinnerCounter()
    let groupFinished = AsyncGate()

    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let token = registry.register(
        continuation: continuation,
        stage: .eject,
        elapsed: { 0.5 }
      )

      Task { @concurrent in
        await withTaskGroup(of: Bool.self) { group in
          group.addTask {
            registry.completeFromCallback(token: token, error: nil, rawStatus: nil)
          }
          group.addTask {
            registry.completeAsTimeout(token: token)
          }
          group.addTask {
            registry.completeAsCancelled(token: token)
          }

          for await won in group where won {
            winnerCount.increment()
          }
        }
        await groupFinished.open()
      }
    }

    #expect(result.stage == .eject)
    #expect(registry.pendingCount == 0)

    await groupFinished.wait()
    #expect(winnerCount.value == 1)
  }

  @Test("Late, duplicate, unknown, and nil callback contexts are harmless")
  func lateAndUnknownCallbacks() async {
    let registry = DiskOperationRegistry()
    let token = await timeoutToken(in: registry)

    #expect(!registry.completeFromCallback(token: token, error: nil, rawStatus: nil))
    #expect(!registry.completeFromCallback(token: token, error: nil, rawStatus: nil))
    #expect(!registry.completeFromCallback(token: token &+ 100, error: nil, rawStatus: nil))
    #expect(unsafe DiskArbitrationUnsafeAdapter.token(from: nil) == nil)
    #expect(registry.pendingCount == 0)
  }

  @Test("Repeated missing callbacks release every registry entry")
  func missingCallbacksDoNotLeakRegistryEntries() async {
    let registry = DiskOperationRegistry()

    for _ in 0..<1_000 {
      _ = await timeoutToken(in: registry)
      #expect(registry.pendingCount == 0)
    }
  }

  @Test("Token zero is skipped and rollover does not collide")
  func tokenRollover() async {
    let registry = DiskOperationRegistry(startingToken: UInt.max)

    let first = await registeredToken(in: registry, expected: UInt.max)
    let second = await registeredToken(in: registry, expected: 1)

    #expect(first == UInt.max)
    #expect(second == 1)
    #expect(first != 0)
    #expect(second != 0)
    #expect(registry.pendingCount == 0)
  }

  @Test("Opaque context cookies round trip without dereferencing memory")
  func contextCookieRoundTrip() {
    for token: UInt in [1, 2, 42, UInt(Int.max)] {
      let pointer = unsafe DiskArbitrationUnsafeAdapter.contextPointer(for: token)
      #expect(unsafe DiskArbitrationUnsafeAdapter.token(from: pointer) == token)
    }
  }

  @Test("Result construction can re-enter the registry")
  func resumeOutsideMutex() async {
    let registry = DiskOperationRegistry()
    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let token = registry.register(
        continuation: continuation,
        stage: .unmount,
        elapsed: {
          // Deadlocks if the elapsed/result factory runs while the mutex is held.
          #expect(registry.pendingCount == 0)
          return 0.75
        }
      )
      #expect(registry.completeAsTimeout(token: token))
    }

    #expect(result.duration == 0.75)
    #expect(registry.pendingCount == 0)
  }

  @Test("Cancellation before the submission linearization point prevents commit")
  func cancellationBeforeSubmission() async {
    let registry = DiskOperationRegistry()
    let committed = Mutex<Bool?>(nil)
    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let token = registry.register(
        continuation: continuation,
        stage: .unmount,
        elapsed: { 0 }
      )
      #expect(registry.completeAsCancelled(token: token))
      committed.withLock { $0 = registry.commitSubmission(for: token) }
    }

    #expect(result.error?.category == .cancelled)
    #expect(committed.withLock { $0 } == false)
    #expect(registry.pendingCount == 0)
  }

  private func timeoutToken(in registry: DiskOperationRegistry) async -> UInt {
    let tokenBox = Mutex<UInt?>(nil)
    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let token = registry.register(
        continuation: continuation,
        stage: .unmount,
        elapsed: { 1 }
      )
      tokenBox.withLock { $0 = token }
      #expect(registry.completeAsTimeout(token: token))
    }
    #expect(result.error?.category == .timeout)
    return tokenBox.withLock { $0! }
  }

  private func registeredToken(
    in registry: DiskOperationRegistry,
    expected: UInt
  ) async -> UInt {
    let tokenBox = Mutex<UInt?>(nil)
    _ = await withCheckedContinuation { (continuation: CheckedContinuation<DiskOperationResult, Never>) in
      let token = registry.register(
        continuation: continuation,
        stage: .unmount,
        elapsed: { 0 }
      )
      tokenBox.withLock { $0 = token }
      #expect(token == expected)
      #expect(registry.completeAsCancelled(token: token))
    }
    return tokenBox.withLock { $0! }
  }

  enum Completion: Sendable {
    case callback
    case timeout
    case cancelled
  }
}

private final class WinnerCounter: Sendable {
  private let count = Mutex(0)

  var value: Int { count.withLock { $0 } }

  func increment() {
    count.withLock { $0 += 1 }
  }
}

private actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    guard !isOpen else { return }
    isOpen = true
    let continuations = waiters
    waiters.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }
}

extension Tag {
  @Tag static var concurrency: Self
}
