import Foundation
import SwiftDiskArbitration
import Testing
@testable import EjectAllDisksPlugin

private let context = "test-context"
private let actionID = ActionInstanceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
private let subscriptionID = SubscriptionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
private let operationID = EjectOperationID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
private let otherOperationID = EjectOperationID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
private let disk2 = PhysicalDeviceID(rawValue: "disk2")
private let disk3 = PhysicalDeviceID(rawValue: "disk3")

private func appearance(
    instanceID: ActionInstanceID = actionID,
    subscriptionID: SubscriptionID = subscriptionID,
    showTitle: Bool = true
) -> ActionAppearance {
    ActionAppearance(
        context: context,
        instanceID: instanceID,
        subscriptionID: subscriptionID,
        device: "stream-deck",
        settings: EjectActionSettings(showTitle: showTitle)
    )
}

private func checkingState() -> EjectCoordinatorState {
    EjectReducer.reduce(state: .inactive, event: .actionAppeared(appearance())).state
}

private func readyState(count: Int = 2) -> EjectCoordinatorState {
    EjectReducer.reduce(
        state: checkingState(),
        event: .inventoryResolved(
            generation: 1,
            reason: .firstAppearance,
            .available(ejectableVolumeCount: count)
        )
    ).state
}

private func ejectingState() -> EjectCoordinatorState {
    let release = ActionKeyRelease(
        context: context,
        instanceID: actionID,
        longPress: false,
        settings: EjectActionSettings()
    )
    return EjectReducer.reduce(
        state: readyState(),
        event: .keyReleased(release),
        newOperationID: operationID
    ).state
}

private func batchResult(total: Int, succeeded: Int) -> BatchEjectResult {
    let results = (0..<total).map { index in
        let success = index < succeeded
        return SingleEjectResult(
            volumeName: "Private Name \(index)",
            volumePath: "/Volumes/Private Name \(index)",
            bsdName: "disk\(index + 2)s1",
            success: success,
            errorMessage: success ? nil : "busy",
            errorCategory: success ? nil : .busy,
            errorStage: success ? nil : .unmount,
            duration: 0.1
        )
    }
    return BatchEjectResult(
        totalCount: total,
        successCount: succeeded,
        failedCount: total - succeeded,
        results: results,
        totalDuration: 0.1
    )
}

private extension Array where Element == EjectEffect {
    var beginsOperation: Bool {
        contains { if case .beginOperation = $0 { true } else { false } }
    }

    var startsMonitoring: Bool {
        contains { if case .startMonitoring = $0 { true } else { false } }
    }

    var stopsMonitoring: Bool {
        contains { if case .stopMonitoring = $0 { true } else { false } }
    }
}

@Suite("SafeEject pure reducer")
struct EjectReducerTests {
    @Test("Initial appearance is checking and starts one monitor")
    func initialAppearance() {
        let reduction = EjectReducer.reduce(
            state: .inactive,
            event: .actionAppeared(appearance())
        )
        guard case .checking(let actions) = reduction.state else {
            Issue.record("Expected checking state")
            return
        }
        #expect(actions.byContext.count == 1)
        #expect(reduction.effects.startsMonitoring)
        #expect(EjectPresentation.make(
            state: reduction.state,
            settings: EjectActionSettings()
        ).title == "Checking…")
    }

    @Test("Fresh inventory resolves checking without inventing zero")
    func inventoryResolution() {
        let state = readyState(count: 0)
        guard case .ready(let ready) = state else {
            Issue.record("Expected ready state")
            return
        }
        #expect(ready.inventory == .available(ejectableVolumeCount: 0))
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "No Disks")
    }

    @Test("No-disk operation is neutral and never shows a green confirmation")
    func noDiskOperationIsNeutral() {
        let reduction = EjectReducer.reduce(
            state: ejectingState(),
            event: .operationCompleted(operationID, batchResult(total: 0, succeeded: 0))
        )

        #expect(EjectPresentation.make(
            state: reduction.state,
            settings: EjectActionSettings()
        ).title == "No Disks")
        #expect(reduction.effects.contains {
            if case .renderAll(nil) = $0 { true } else { false }
        })
        #expect(!reduction.effects.contains {
            if case .renderAll(.ok) = $0 { true } else { false }
        })
    }

    @Test("Session unavailable presents Failed, not No Disks")
    func unavailableInventory() {
        let state = EjectReducer.reduce(
            state: checkingState(),
            event: .inventoryResolved(generation: 1, reason: .firstAppearance, .unavailable)
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Failed")
    }

    @Test("Short key release starts exactly one active operation")
    func singleAdmissionGate() {
        let release = ActionKeyRelease(
            context: context,
            instanceID: actionID,
            longPress: false,
            settings: EjectActionSettings()
        )
        let first = EjectReducer.reduce(
            state: readyState(),
            event: .keyReleased(release),
            newOperationID: operationID
        )
        #expect(first.effects.beginsOperation)
        let second = EjectReducer.reduce(
            state: first.state,
            event: .keyReleased(release),
            newOperationID: otherOperationID
        )
        #expect(!second.effects.beginsOperation)
        #expect(second.state == first.state)
    }

    @Test("Long press does not start an operation")
    func longPressIgnored() {
        let release = ActionKeyRelease(
            context: context,
            instanceID: actionID,
            longPress: true,
            settings: EjectActionSettings()
        )
        let reduction = EjectReducer.reduce(
            state: readyState(),
            event: .keyReleased(release),
            newOperationID: operationID
        )
        #expect(!reduction.effects.beginsOperation)
    }

    @Test("Unmount success is not safe-to-remove")
    func unmountIsNotSuccess() {
        var state = ejectingState()
        state = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(operationID, .unmountStarted(disk2))
        ).state
        state = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(operationID, .unmountCompleted(disk2))
        ).state
        guard case .ejecting(let batch) = state else {
            Issue.record("Expected ejecting state")
            return
        }
        #expect(batch.devices[disk2] == .unmounted)
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title != "Ejected!")
    }

    @Test("Only eject callback success reaches safe-to-remove")
    func ejectSuccessIsAuthoritative() {
        var state = ejectingState()
        for event in [
            DeviceEjectEvent.unmountStarted(disk2),
            .unmountCompleted(disk2),
            .ejectStarted(disk2),
            .completed(disk2, .safeToRemove(duration: 0.2)),
        ] {
            state = EjectReducer.reduce(
                state: state,
                event: .deviceProgress(operationID, event)
            ).state
        }
        state = EjectReducer.reduce(
            state: state,
            event: .operationCompleted(operationID, batchResult(total: 1, succeeded: 1))
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Ejected!")
    }

    @Test("Aggregate success without eject progress remains unconfirmed")
    func missingEjectConfirmation() {
        var state = ejectingState()
        state = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(operationID, .unmountStarted(disk2))
        ).state
        state = EjectReducer.reduce(
            state: state,
            event: .operationCompleted(operationID, batchResult(total: 1, succeeded: 1))
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Check Disk")
    }

    @Test("Busy dissenter overrides pending progress immediately")
    func busyFailureIsImmediate() {
        var state = ejectingState()
        let failure = DeviceEjectFailure(
            deviceID: disk2,
            stage: .unmount,
            category: .busy,
            rawStatus: nil
        )
        state = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(operationID, .completed(disk2, .failed(failure, duration: 0.1)))
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "In Use")
    }

    @Test("Three and fifteen second threshold events are progressive")
    func progressiveFeedback() {
        var state = EjectReducer.reduce(
            state: ejectingState(),
            event: .deviceProgress(operationID, .unmountStarted(disk2))
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Ejecting…")
        state = EjectReducer.reduce(
            state: state,
            event: .slowThresholdReached(operationID, disk2, .unmount)
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Working…")
        state = EjectReducer.reduce(
            state: state,
            event: .attentionThresholdReached(operationID, disk2, .unmount)
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Check Disk")
    }

    @Test("Zero inventory cannot overwrite active operation presentation")
    func zeroInventoryDuringOperation() {
        let state = EjectReducer.reduce(
            state: ejectingState(),
            event: .inventoryResolved(
                generation: 2,
                reason: .workspaceNotification,
                .available(ejectableVolumeCount: 0)
            )
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "Ejecting…")
    }

    @Test("Stale operation progress is ignored")
    func staleProgressIgnored() {
        let state = ejectingState()
        let reduced = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(otherOperationID, .unmountStarted(disk2))
        ).state
        #expect(reduced == state)
    }

    @Test("Mixed safe and failed devices are never overall success")
    func partialFailure() {
        var state = ejectingState()
        let failure = DeviceEjectFailure(
            deviceID: disk3,
            stage: .unmount,
            category: .busy,
            rawStatus: nil
        )
        for event in [
            DeviceEjectEvent.completed(disk2, .safeToRemove(duration: 0.1)),
            .completed(disk3, .failed(failure, duration: 0.1)),
        ] {
            state = EjectReducer.reduce(
                state: state,
                event: .deviceProgress(operationID, event)
            ).state
        }
        state = EjectReducer.reduce(
            state: state,
            event: .operationCompleted(operationID, batchResult(total: 2, succeeded: 1))
        ).state
        #expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "1 of 2\nFailed")
    }

    @Test("Settings update presentation without changing operation")
    func settingsChange() {
        let original = ejectingState()
        let reduced = EjectReducer.reduce(
            state: original,
            event: .settingsChanged(ActionSettingsSnapshot(
                context: context,
                instanceID: actionID,
                settings: EjectActionSettings(showTitle: false)
            ))
        ).state
        guard case .ejecting = reduced else {
            Issue.record("Operation state changed")
            return
        }
        let settings = reduced.visibleActions.byContext[context]?.settings
        #expect(settings == EjectActionSettings(showTitle: false))
        #expect(EjectPresentation.make(state: reduced, settings: settings!).title == nil)
    }

    @Test("Old disappearance cannot remove a replacement instance")
    func staleDisappearance() {
        let replacementID = ActionInstanceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!)
        let replacementSubscription = SubscriptionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        var state = checkingState()
        state = EjectReducer.reduce(
            state: state,
            event: .actionAppeared(appearance(
                instanceID: replacementID,
                subscriptionID: replacementSubscription
            ))
        ).state
        state = EjectReducer.reduce(
            state: state,
            event: .actionDisappeared(ActionDisappearance(
                context: context,
                instanceID: actionID,
                subscriptionID: subscriptionID
            ))
        ).state
        #expect(state.visibleActions.byContext[context]?.instanceID == replacementID)
    }

	@Test("Failure survives drift polling and clears only on a topology refresh")
	func failureLifecycle() {
        var state = ejectingState()
        let failure = DeviceEjectFailure(
            deviceID: disk2,
            stage: .unmount,
            category: .busy,
            rawStatus: nil
        )
        state = EjectReducer.reduce(
            state: state,
            event: .deviceProgress(operationID, .completed(disk2, .failed(failure, duration: 0.1)))
        ).state
        state = EjectReducer.reduce(
            state: state,
            event: .operationCompleted(operationID, batchResult(total: 1, succeeded: 0))
        ).state

        // The refresh issued by completion itself must not erase the failure.
        let immediate = EjectReducer.reduce(
            state: state,
            event: .inventoryResolved(
                generation: 2,
                reason: .operationCompleted,
                .available(ejectableVolumeCount: 1)
            )
        ).state
        #expect(EjectPresentation.make(state: immediate, settings: EjectActionSettings()).title == "In Use")

        let afterFallback = EjectReducer.reduce(
            state: immediate,
            event: .inventoryResolved(
                generation: 3,
                reason: .fallback,
                .available(ejectableVolumeCount: 1)
            )
        ).state
        guard case .completed = afterFallback else {
            Issue.record("Expected fallback polling to preserve the failure")
            return
        }
        #expect(EjectPresentation.make(state: afterFallback, settings: EjectActionSettings()).title == "In Use")

        let afterTopologyChange = EjectReducer.reduce(
            state: afterFallback,
            event: .inventoryResolved(
                generation: 4,
                reason: .workspaceNotification,
                .available(ejectableVolumeCount: 1)
            )
        ).state
        guard case .ready = afterTopologyChange else {
            Issue.record("Expected a topology refresh to clear the prior failure")
            return
        }
        #expect(EjectPresentation.make(
            state: afterTopologyChange,
            settings: EjectActionSettings()
		).title == "1 Disk")
	}

	@Test("Pressing an In Use key immediately retries the eject operation")
	func failedOperationRetriesOnPress() {
		var state = ejectingState()
		let failure = DeviceEjectFailure(
			deviceID: disk2,
			stage: .unmount,
			category: .busy,
			rawStatus: nil
		)
		state = EjectReducer.reduce(
			state: state,
			event: .deviceProgress(operationID, .completed(disk2, .failed(failure, duration: 0.1)))
		).state
		state = EjectReducer.reduce(
			state: state,
			event: .operationCompleted(operationID, batchResult(total: 1, succeeded: 0))
		).state
		#expect(EjectPresentation.make(state: state, settings: EjectActionSettings()).title == "In Use")

		let retry = EjectReducer.reduce(
			state: state,
			event: .keyReleased(ActionKeyRelease(
				context: context,
				instanceID: actionID,
				longPress: false,
				settings: EjectActionSettings()
			)),
			newOperationID: otherOperationID
		)

		guard case .ejecting(let batch) = retry.state else {
			Issue.record("Expected the failed key press to start a fresh eject operation")
			return
		}
		#expect(batch.operationID == otherOperationID)
		#expect(retry.effects.beginsOperation)
		#expect(EjectPresentation.make(state: retry.state, settings: EjectActionSettings()).title == "Ejecting…")
	}

	@Test("Replacing a context releases the prior instance render token")
    func replacementReleasesRenderToken() {
        let replacementID = ActionInstanceID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!)
        let replacementSubscription = SubscriptionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        let reduction = EjectReducer.reduce(
            state: checkingState(),
            event: .actionAppeared(appearance(
                instanceID: replacementID,
                subscriptionID: replacementSubscription
            ))
        )

        #expect(reduction.effects.contains {
            if case .releaseRenderToken(actionID) = $0 { true } else { false }
        })
        #expect(reduction.state.visibleActions.byContext[context]?.instanceID == replacementID)
    }

    @Test("Disappearance releases the instance render token")
    func disappearanceReleasesRenderToken() {
        let reduction = EjectReducer.reduce(
            state: checkingState(),
            event: .actionDisappeared(ActionDisappearance(
                context: context,
                instanceID: actionID,
                subscriptionID: subscriptionID
            ))
        )
        #expect(reduction.effects.contains {
            if case .releaseRenderToken(actionID) = $0 { true } else { false }
        })
    }

    @Test("Final disappearance stops monitoring and cancels active work")
    func finalDisappearance() {
        let reduction = EjectReducer.reduce(
            state: ejectingState(),
            event: .actionDisappeared(ActionDisappearance(
                context: context,
                instanceID: actionID,
                subscriptionID: subscriptionID
            ))
        )
        #expect(reduction.state == .inactive)
        #expect(reduction.effects.stopsMonitoring)
        #expect(reduction.effects.contains { if case .cancelOperation = $0 { true } else { false } })
    }
}

@Suite("Ordered event ingress")
struct EventIngressTests {
    @Test("Lifecycle submission is sequenced and disappearance invalidates synchronously")
    func orderedLifecycle() async throws {
        let registry = ActiveActionRegistry()
        let ingress = EventIngress(activeActions: registry)
        var iterator = ingress.events.makeAsyncIterator()

        ingress.submit(.actionAppeared(appearance()))
        #expect(registry.isActive(context: context, instanceID: actionID))
        ingress.submit(.actionDisappeared(ActionDisappearance(
            context: context,
            instanceID: actionID,
            subscriptionID: subscriptionID
        )))
        #expect(!registry.isActive(context: context, instanceID: actionID))

        let first = try #require(await iterator.next())
        let second = try #require(await iterator.next())
        #expect(first.sequence < second.sequence)
    }

    @Test("Concurrent lifecycle publication and renderer tokens stay in the same order")
    func concurrentLifecycleLinearization() async throws {
        let registry = ActiveActionRegistry()
        let ingress = EventIngress(activeActions: registry)
        var iterator = ingress.events.makeAsyncIterator()

        for _ in 0..<500 {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    ingress.submit(.actionAppeared(appearance()))
                }
                group.addTask {
                    ingress.submit(.actionDisappeared(ActionDisappearance(
                        context: context,
                        instanceID: actionID,
                        subscriptionID: subscriptionID
                    )))
                }
            }

            let first = try #require(await iterator.next())
            let second = try #require(await iterator.next())
            #expect(first.sequence < second.sequence)

            switch second.event {
            case .actionAppeared:
                #expect(registry.isActive(context: context, instanceID: actionID))
            case .actionDisappeared:
                #expect(!registry.isActive(context: context, instanceID: actionID))
            default:
                Issue.record("Unexpected non-lifecycle event")
            }
        }
    }

    @Test("Context reuse protects the newer token from an old disappearance")
    func contextReuse() {
        let registry = ActiveActionRegistry()
        let ingress = EventIngress(activeActions: registry)
        let newerID = ActionInstanceID()
        let newerSubscription = SubscriptionID()

        ingress.submit(.actionAppeared(appearance()))
        ingress.submit(.actionAppeared(appearance(
            instanceID: newerID,
            subscriptionID: newerSubscription
        )))
        ingress.submit(.actionDisappeared(ActionDisappearance(
            context: context,
            instanceID: actionID,
            subscriptionID: subscriptionID
        )))
        #expect(registry.isActive(context: context, instanceID: newerID))
    }
}
