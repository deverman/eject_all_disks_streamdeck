import Foundation
import SwiftDiskArbitration

enum EjectEffect: Sendable {
    case startMonitoring
    case stopMonitoring
    case refreshInventory(InventoryRefreshReason)
    case beginOperation(EjectOperationID)
    case cancelOperation
    case seedSettings(context: String, instanceID: ActionInstanceID, EjectActionSettings)
    case releaseRenderToken(ActionInstanceID)
    case renderAll(KeyFeedback?)
    case renderOne(context: String, KeyFeedback?)
    case scheduleThresholds(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case cancelThresholds(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case scheduleCompletionReset(EjectOperationID)
}

struct EjectReduction: Sendable {
    let state: EjectCoordinatorState
    let effects: [EjectEffect]
}

/// Pure state transition engine. UUID allocation, clocks, disk access, Stream
/// Deck transport, and task ownership all remain in `EjectCoordinator`.
enum EjectReducer {
    static func reduce(
        state original: EjectCoordinatorState,
        event: EjectEvent,
        newOperationID: EjectOperationID? = nil
    ) -> EjectReduction {
        var state = original
        var effects: [EjectEffect] = []

        switch event {
        case .actionAppeared(let appearance):
            let wasEmpty = state.visibleActions.isEmpty
            let replacedInstanceID = state.visibleActions.byContext[appearance.context]?.instanceID
            var actions = state.visibleActions
            actions.byContext[appearance.context] = VisibleAction(
                context: appearance.context,
                instanceID: appearance.instanceID,
                subscriptionID: appearance.subscriptionID,
                device: appearance.device,
                settings: appearance.settings
            )
            state.visibleActions = actions
            if let replacedInstanceID, replacedInstanceID != appearance.instanceID {
                effects.append(.releaseRenderToken(replacedInstanceID))
            }
            effects.append(.seedSettings(
                context: appearance.context,
                instanceID: appearance.instanceID,
                appearance.settings
            ))
            if wasEmpty {
                state = .checking(actions)
                effects.append(.startMonitoring)
                effects.append(.refreshInventory(.firstAppearance))
            }
            effects.append(.renderOne(context: appearance.context, nil))

        case .actionDisappeared(let disappearance):
            guard let current = state.visibleActions.byContext[disappearance.context],
                current.instanceID == disappearance.instanceID,
                current.subscriptionID == disappearance.subscriptionID
            else { break }

            var actions = state.visibleActions
            actions.byContext.removeValue(forKey: disappearance.context)
            state.visibleActions = actions
            effects.append(.releaseRenderToken(disappearance.instanceID))
            if actions.isEmpty {
                if case .ejecting = original { effects.append(.cancelOperation) }
                state = .inactive
                effects.append(.stopMonitoring)
            }

        case .settingsChanged(let snapshot):
            guard var action = state.visibleActions.byContext[snapshot.context],
                action.instanceID == snapshot.instanceID
            else { break }
            action.settings = snapshot.settings
            var actions = state.visibleActions
            actions.byContext[snapshot.context] = action
            state.visibleActions = actions
            effects.append(.renderOne(context: snapshot.context, nil))

        case .keyReleased(let release):
            guard !release.longPress,
                var action = state.visibleActions.byContext[release.context],
                action.instanceID == release.instanceID
            else { break }
            guard case .ejecting = state else {
                guard let operationID = newOperationID else { break }
                action.settings = release.settings
                var actions = state.visibleActions
                actions.byContext[release.context] = action
                state = .ejecting(BatchEjectState(
                    visibleActions: actions,
                    inventory: state.inventory,
                    operationID: operationID,
                    devices: [:]
                ))
                effects.append(.renderAll(nil))
                effects.append(.beginOperation(operationID))
                break
            }
            // The coordinator's active operation is the single admission gate.

        case .inventoryRefreshRequested(let reason):
            guard !state.visibleActions.isEmpty else { break }
            effects.append(.refreshInventory(reason))

        case .inventoryResolved(_, let reason, let inventory):
            guard !state.visibleActions.isEmpty else { break }
            if case .completed(let summary) = state,
                !summary.allDevicesSafeToRemove,
                !summary.hadNoDisks,
                reason == .wake || reason == .workspaceNotification
            {
                state = .ready(ReadyEjectState(
                    visibleActions: summary.visibleActions,
                    inventory: inventory
                ))
            } else {
                state.inventory = inventory
            }
            effects.append(.renderAll(nil))

        case .operationUnavailable(let operationID):
            guard case .ejecting(let batch) = state, batch.operationID == operationID else { break }
            let sessionID = PhysicalDeviceID(rawValue: "session")
            let failure = DeviceEjectFailure(
                deviceID: sessionID,
                stage: .unmount,
                category: .session,
                rawStatus: nil
            )
            state = .completed(BatchEjectSummary(
                visibleActions: batch.visibleActions,
                inventory: .unavailable,
                operationID: operationID,
                devices: [sessionID: .failed(failure)],
                totalVolumeCount: 0,
                successfulVolumeCount: 0,
                failedVolumeCount: 1,
                hadNoDisks: false
            ))
            effects.append(.renderAll(.alert))

        case .deviceProgress(let operationID, let progress):
            guard case .ejecting(var batch) = state, batch.operationID == operationID else { break }
            let deviceID = progress.deviceID
            let previous = batch.devices[deviceID]
            switch progress {
            case .unmountStarted:
                batch.devices[deviceID] = .unmounting(.normal)
                effects.append(.scheduleThresholds(operationID, deviceID, .unmount))
            case .unmountCompleted:
                batch.devices[deviceID] = .unmounted
                effects.append(.cancelThresholds(operationID, deviceID, .unmount))
            case .ejectStarted:
                batch.devices[deviceID] = .ejecting(.normal)
                effects.append(.cancelThresholds(operationID, deviceID, .unmount))
                effects.append(.scheduleThresholds(operationID, deviceID, .eject))
            case .completed(_, let outcome):
                if let previousStage = previous?.activeStage {
                    effects.append(.cancelThresholds(operationID, deviceID, previousStage))
                }
                switch outcome {
                case .safeToRemove:
                    batch.devices[deviceID] = .safeToRemove
                case .unmounted:
                    batch.devices[deviceID] = .unmounted
                case .failed(let failure, _):
                    batch.devices[deviceID] = .failed(failure)
                    effects.append(.renderAll(.alert))
                case .timedOut(let stage, _):
                    batch.devices[deviceID] = .timedOut(stage: stage)
                    effects.append(.renderAll(.alert))
                case .cancelled:
                    batch.devices[deviceID] = .cancelled
                }
            }
            state = .ejecting(batch)
            if !effects.containsRender { effects.append(.renderAll(nil)) }

        case .slowThresholdReached(let operationID, let deviceID, let stage):
            guard case .ejecting(var batch) = state, batch.operationID == operationID,
                batch.devices[deviceID]?.activeStage == stage
            else { break }
            batch.devices[deviceID] = stage == .unmount ? .unmounting(.slow) : .ejecting(.slow)
            state = .ejecting(batch)
            effects.append(.renderAll(nil))

        case .attentionThresholdReached(let operationID, let deviceID, let stage):
            guard case .ejecting(var batch) = state, batch.operationID == operationID,
                batch.devices[deviceID]?.activeStage == stage
            else { break }
            batch.devices[deviceID] = stage == .unmount ? .unmounting(.attention) : .ejecting(.attention)
            state = .ejecting(batch)
            effects.append(.renderAll(nil))

        case .operationCompleted(let operationID, let result):
            guard case .ejecting(let batch) = state, batch.operationID == operationID else { break }
            var terminalDevices = batch.devices
            for (deviceID, deviceState) in terminalDevices where !deviceState.isTerminal {
                // Never infer safe removal from a count or aggregate success. If
                // the authoritative eject-success progress event is missing,
                // preserve the result as unconfirmed.
                terminalDevices[deviceID] = .disappearedWithoutEjectConfirmation
            }
            let summary = BatchEjectSummary(
                visibleActions: batch.visibleActions,
                inventory: batch.inventory,
                operationID: operationID,
                devices: terminalDevices,
                totalVolumeCount: result.totalCount,
                successfulVolumeCount: result.successCount,
                failedVolumeCount: result.failedCount,
                hadNoDisks: result.totalCount == 0
            )
            state = .completed(summary)
            // Green is reserved for a confirmed physical-device eject callback.
            // Pressing the key with no mounted disks is a neutral no-op.
            let feedback: KeyFeedback? = summary.hadNoDisks
                ? nil
                : (summary.allDevicesSafeToRemove ? .ok : .alert)
            effects.append(.renderAll(feedback))
            effects.append(.refreshInventory(.operationCompleted))
            if summary.hadNoDisks || summary.allDevicesSafeToRemove {
                effects.append(.scheduleCompletionReset(operationID))
            }

        case .completionDisplayExpired(let operationID):
            guard case .completed(let summary) = state,
                summary.operationID == operationID,
                summary.hadNoDisks || summary.allDevicesSafeToRemove
            else { break }
            state = .ready(ReadyEjectState(
                visibleActions: summary.visibleActions,
                inventory: summary.inventory
            ))
            effects.append(.renderAll(nil))

        case .systemWoke:
            guard !state.visibleActions.isEmpty else { break }
            effects.append(.refreshInventory(.wake))
        }

        return EjectReduction(state: state, effects: effects)
    }
}

private extension DeviceEjectEvent {
    var deviceID: PhysicalDeviceID {
        switch self {
        case .unmountStarted(let id), .unmountCompleted(let id), .ejectStarted(let id), .completed(let id, _):
            return id
        }
    }
}

private extension DeviceEjectState {
    var activeStage: DiskOperationStage? {
        switch self {
        case .unmounting:
            return .unmount
        case .ejecting:
            return .eject
        default:
            return nil
        }
    }

    var isTerminal: Bool {
        switch self {
        case .safeToRemove, .failed, .timedOut, .cancelled, .disappearedWithoutEjectConfirmation:
            return true
        default:
            return false
        }
    }
}

private extension Array where Element == EjectEffect {
    var containsRender: Bool {
        contains { effect in
            switch effect {
            case .renderAll, .renderOne:
                return true
            default:
                return false
            }
        }
    }
}
