import Foundation
import SwiftDiskArbitration
import Synchronization

struct ActionAppearance: Sendable {
    let context: String
    let instanceID: ActionInstanceID
    let subscriptionID: SubscriptionID
    let device: String
    let settings: EjectActionSettings
}

struct ActionDisappearance: Sendable {
    let context: String
    let instanceID: ActionInstanceID
    let subscriptionID: SubscriptionID
}

struct ActionSettingsSnapshot: Sendable {
    let context: String
    let instanceID: ActionInstanceID
    let settings: EjectActionSettings
}

struct ActionKeyRelease: Sendable {
    let context: String
    let instanceID: ActionInstanceID
    let longPress: Bool
    let settings: EjectActionSettings
}

enum InventoryRefreshReason: Sendable, Equatable {
    case firstAppearance
    case workspaceNotification
    case wake
    case fallback
    case operationCompleted
}

enum EjectEvent: Sendable {
    case actionAppeared(ActionAppearance)
    case actionDisappeared(ActionDisappearance)
    case settingsChanged(ActionSettingsSnapshot)
    case keyReleased(ActionKeyRelease)
    case inventoryRefreshRequested(InventoryRefreshReason)
    case inventoryResolved(generation: UInt64, reason: InventoryRefreshReason, DiskInventoryState)
    case operationUnavailable(EjectOperationID)
    case deviceProgress(EjectOperationID, DeviceEjectEvent)
    case slowThresholdReached(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case attentionThresholdReached(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case operationCompleted(EjectOperationID, BatchEjectResult)
    case completionDisplayExpired(EjectOperationID)
    case systemWoke
}

struct SequencedEjectEvent: Sendable {
    let sequence: UInt64
    let event: EjectEvent
}

/// Synchronous token registry used by callbacks and the renderer. Deactivation
/// happens before `willDisappear` returns, so queued work cannot render to an
/// action instance that Stream Deck has already removed.
final class ActiveActionRegistry: Sendable {
    private let active = Mutex<[String: ActionInstanceID]>([:])

    func activate(context: String, instanceID: ActionInstanceID) {
        active.withLock { $0[context] = instanceID }
    }

    func deactivate(context: String, instanceID: ActionInstanceID) {
        active.withLock { state in
            guard state[context] == instanceID else { return }
            state.removeValue(forKey: context)
        }
    }

    func isActive(context: String, instanceID: ActionInstanceID) -> Bool {
        active.withLock { $0[context] == instanceID }
    }
}

/// Establishes one total order for Stream Deck, monitor, timer, and disk events.
/// The stream is intentionally unbounded because lifecycle events may not be
/// discarded. Its one consumer lives for the plugin process lifetime.
final class EventIngress: Sendable {
    private struct State: Sendable {
        var nextSequence: UInt64 = 1
        let continuation: AsyncStream<SequencedEjectEvent>.Continuation
    }

    let events: AsyncStream<SequencedEjectEvent>
    let activeActions: ActiveActionRegistry
    private let state: Mutex<State>

    init(activeActions: ActiveActionRegistry) {
        let pair = AsyncStream<SequencedEjectEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = pair.stream
        self.activeActions = activeActions
        self.state = Mutex(State(continuation: pair.continuation))
    }

    func submit(_ event: EjectEvent) {
        state.withLock { state in
            // Lifecycle-token mutation and stream publication share this
            // linearization point. Keeping them in one critical section means
            // concurrent appearance/disappearance submissions cannot publish
            // one order while leaving the renderer registry in another.
            switch event {
            case .actionAppeared(let appearance):
                activeActions.activate(context: appearance.context, instanceID: appearance.instanceID)
            case .actionDisappeared(let disappearance):
                activeActions.deactivate(context: disappearance.context, instanceID: disappearance.instanceID)
            default:
                break
            }

            let sequence = state.nextSequence
            state.nextSequence &+= 1
            if state.nextSequence == 0 { state.nextSequence = 1 }
            state.continuation.yield(SequencedEjectEvent(sequence: sequence, event: event))
        }
    }
}
