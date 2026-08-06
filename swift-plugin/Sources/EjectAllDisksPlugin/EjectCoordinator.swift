import Foundation
import OSLog
import SwiftDiskArbitration

private let coordinatorLog = Logger(subsystem: "org.deverman.ejectalldisks", category: "coordinator")

private struct ThresholdKey: Hashable, Sendable {
    let operationID: EjectOperationID
    let deviceID: PhysicalDeviceID
    let stage: DiskOperationStage
}

private struct ThresholdTasks: Sendable {
    let slow: Task<Void, Never>
    let attention: Task<Void, Never>

    func cancel() {
        slow.cancel()
        attention.cancel()
    }
}

actor EjectCoordinator {
    private var state: EjectCoordinatorState = .inactive
    private let ingress: EventIngress
    private let renderer: StreamDeckRenderer

    private var lifecycleEpoch: UInt64 = 0
    private var inventoryGeneration: UInt64 = 0
    private var renderRevision: UInt64 = 0

    private var inventoryTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var thresholdTasks: [ThresholdKey: ThresholdTasks] = [:]
    private var completionResetTask: Task<Void, Never>?

    init(ingress: EventIngress, renderer: StreamDeckRenderer) {
        self.ingress = ingress
        self.renderer = renderer
    }

    isolated deinit {
        inventoryTask?.cancel()
        operationTask?.cancel()
        completionResetTask?.cancel()
        for tasks in thresholdTasks.values { tasks.cancel() }
    }

    func consume(_ envelope: SequencedEjectEvent) async {
        coordinatorLog.debug("Consuming event sequence \(envelope.sequence, privacy: .public)")

        if case .inventoryResolved(let generation, _, _) = envelope.event,
            generation != inventoryGeneration
        {
            return
        }

        let operationID: EjectOperationID?
        if case .keyReleased(let release) = envelope.event,
            !release.longPress,
            state.visibleActions.byContext[release.context]?.instanceID == release.instanceID
        {
            if case .ejecting = state {
                operationID = nil
            } else {
                operationID = EjectOperationID()
            }
        } else {
            operationID = nil
        }

        let reduction = EjectReducer.reduce(
            state: state,
            event: envelope.event,
            newOperationID: operationID
        )
        state = reduction.state
        for effect in reduction.effects {
            await perform(effect)
        }
    }

    private func perform(_ effect: EjectEffect) async {
        switch effect {
        case .startMonitoring:
            lifecycleEpoch &+= 1
            let epoch = lifecycleEpoch
            let ingress = ingress
            await MainActor.run {
                DiskCountMonitor.shared.start(epoch: epoch, ingress: ingress)
            }

        case .stopMonitoring:
            lifecycleEpoch &+= 1
            let epoch = lifecycleEpoch
            inventoryGeneration &+= 1
            inventoryTask?.cancel()
            inventoryTask = nil
            await MainActor.run {
                DiskCountMonitor.shared.stop(epoch: epoch)
            }

        case .refreshInventory(let reason):
            startInventoryRefresh(reason: reason)

        case .beginOperation(let operationID):
            startOperation(operationID)

        case .cancelOperation:
            operationTask?.cancel()
            operationTask = nil
            cancelAllThresholds()

        case .seedSettings(let context, let instanceID, let settings):
            await renderer.seedSettings(
                context: context,
                instanceID: instanceID,
                settings: settings
            )

        case .releaseRenderToken(let instanceID):
            await renderer.release(instanceID)

        case .renderAll(let feedback):
            for action in state.visibleActions.values {
                await render(action: action, feedback: feedback)
            }

        case .renderOne(let context, let feedback):
            guard let action = state.visibleActions.byContext[context] else { return }
            await render(action: action, feedback: feedback)

        case .scheduleThresholds(let operationID, let deviceID, let stage):
            scheduleThresholds(operationID: operationID, deviceID: deviceID, stage: stage)

        case .cancelThresholds(let operationID, let deviceID, let stage):
            cancelThresholds(operationID: operationID, deviceID: deviceID, stage: stage)

        case .scheduleCompletionReset(let operationID):
            completionResetTask?.cancel()
            let ingress = ingress
            completionResetTask = Task { @concurrent in
                do {
                    try await ContinuousClock().sleep(for: .seconds(2))
                    ingress.submit(.completionDisplayExpired(operationID))
                } catch {
                    // Cancellation means a newer operation or lifecycle won.
                }
            }
        }
    }

    private func startInventoryRefresh(reason: InventoryRefreshReason) {
        inventoryGeneration &+= 1
        let generation = inventoryGeneration
        inventoryTask?.cancel()
        let ingress = ingress
        inventoryTask = Task { @concurrent in
            guard !Task.isCancelled else { return }
            guard let session = DiskSession.shared else {
                ingress.submit(.inventoryResolved(
                    generation: generation,
                    reason: reason,
                    .unavailable
                ))
                return
            }
            let count = await session.ejectableVolumeCount()
            guard !Task.isCancelled else { return }
            ingress.submit(.inventoryResolved(
                generation: generation,
                reason: reason,
                .available(ejectableVolumeCount: count)
            ))
        }
    }

    private func startOperation(_ operationID: EjectOperationID) {
        operationTask?.cancel()
        completionResetTask?.cancel()
        cancelAllThresholds()
        let ingress = ingress

        operationTask = Task { @concurrent in
            guard let session = DiskSession.shared else {
                ingress.submit(.operationUnavailable(operationID))
                return
            }

            let volumes = await session.enumerateEjectableVolumes()
            guard !Task.isCancelled else { return }

            let result = await session.ejectAll(volumes, options: .default) { progress in
                ingress.submit(.deviceProgress(operationID, progress))
            }
            guard !Task.isCancelled else { return }
            ingress.submit(.operationCompleted(operationID, result))
        }
    }

    private func scheduleThresholds(
        operationID: EjectOperationID,
        deviceID: PhysicalDeviceID,
        stage: DiskOperationStage
    ) {
        let key = ThresholdKey(operationID: operationID, deviceID: deviceID, stage: stage)
        thresholdTasks.removeValue(forKey: key)?.cancel()
        let ingress = ingress

        let slow = Task { @concurrent in
            do {
                try await ContinuousClock().sleep(for: .seconds(3))
                ingress.submit(.slowThresholdReached(operationID, deviceID, stage))
            } catch {}
        }
        let attention = Task { @concurrent in
            do {
                try await ContinuousClock().sleep(for: .seconds(15))
                ingress.submit(.attentionThresholdReached(operationID, deviceID, stage))
            } catch {}
        }
        thresholdTasks[key] = ThresholdTasks(slow: slow, attention: attention)
    }

    private func cancelThresholds(
        operationID: EjectOperationID,
        deviceID: PhysicalDeviceID,
        stage: DiskOperationStage
    ) {
        let key = ThresholdKey(operationID: operationID, deviceID: deviceID, stage: stage)
        thresholdTasks.removeValue(forKey: key)?.cancel()
    }

    private func cancelAllThresholds() {
        let tasks = thresholdTasks.values
        thresholdTasks.removeAll()
        for task in tasks { task.cancel() }
    }

    private func render(action: VisibleAction, feedback: KeyFeedback?) async {
        renderRevision &+= 1
        if renderRevision == 0 { renderRevision = 1 }
        let request = RenderRequest(
            context: action.context,
            instanceID: action.instanceID,
            revision: renderRevision,
            presentation: EjectPresentation.make(
                state: state,
                settings: action.settings,
                feedback: feedback
            )
        )
        await renderer.render(request)
    }
}

/// Explicit process-lifetime owner for the unbounded ingress stream and its one
/// consumer. The consumer captures the stream and coordinator, never an action.
final class PluginRuntime: Sendable {
    static let shared = PluginRuntime()

    let ingress: EventIngress
    private let consumerTask: Task<Void, Never>

    private init() {
        let activeActions = ActiveActionRegistry()
        let ingress = EventIngress(activeActions: activeActions)
        let renderer = StreamDeckRenderer(activeActions: activeActions)
        let coordinator = EjectCoordinator(ingress: ingress, renderer: renderer)
        self.ingress = ingress

        let events = ingress.events
        self.consumerTask = Task { @concurrent in
            for await event in events {
                await coordinator.consume(event)
            }
        }
    }

    deinit {
        consumerTask.cancel()
    }
}
