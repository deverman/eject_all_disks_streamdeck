import Foundation
import SwiftDiskArbitration

struct ActionInstanceID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct SubscriptionID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct EjectOperationID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum DiskInventoryState: Sendable, Equatable {
    case checking
    case available(ejectableVolumeCount: Int)
    case unavailable
}

enum WaitStatus: Sendable, Equatable {
    case normal
    case slow
    case attention
}

enum DeviceEjectState: Sendable, Equatable {
    case unmounting(WaitStatus)
    case unmounted
    case ejecting(WaitStatus)
    case safeToRemove
    case failed(DeviceEjectFailure)
    case timedOut(stage: DiskOperationStage)
    case cancelled
    case disappearedWithoutEjectConfirmation
}

struct VisibleAction: Sendable, Equatable {
    let context: String
    let instanceID: ActionInstanceID
    let subscriptionID: SubscriptionID
    let device: String
    var settings: EjectActionSettings
}

struct VisibleActions: Sendable, Equatable {
    var byContext: [String: VisibleAction] = [:]

    var isEmpty: Bool { byContext.isEmpty }
    var values: Dictionary<String, VisibleAction>.Values { byContext.values }
}

struct ReadyEjectState: Sendable, Equatable {
    var visibleActions: VisibleActions
    var inventory: DiskInventoryState
}

struct BatchEjectState: Sendable, Equatable {
    var visibleActions: VisibleActions
    var inventory: DiskInventoryState
    let operationID: EjectOperationID
    var devices: [PhysicalDeviceID: DeviceEjectState]
}

struct BatchEjectSummary: Sendable, Equatable {
    var visibleActions: VisibleActions
    var inventory: DiskInventoryState
    let operationID: EjectOperationID
    let devices: [PhysicalDeviceID: DeviceEjectState]
    let totalVolumeCount: Int
    let successfulVolumeCount: Int
    let failedVolumeCount: Int
    let hadNoDisks: Bool

    var allDevicesSafeToRemove: Bool {
        !devices.isEmpty && devices.values.allSatisfy { $0 == .safeToRemove }
    }

    var hasUnconfirmedDevice: Bool {
        devices.values.contains { device in
            switch device {
            case .timedOut, .disappearedWithoutEjectConfirmation:
                true
            default:
                false
            }
        }
    }
}

enum EjectCoordinatorState: Sendable, Equatable {
    case inactive
    case checking(VisibleActions)
    case ready(ReadyEjectState)
    case ejecting(BatchEjectState)
    case completed(BatchEjectSummary)

    var visibleActions: VisibleActions {
        get {
            switch self {
            case .inactive:
                return VisibleActions()
            case .checking(let actions):
                return actions
            case .ready(let ready):
                return ready.visibleActions
            case .ejecting(let batch):
                return batch.visibleActions
            case .completed(let summary):
                return summary.visibleActions
            }
        }
        set {
            switch self {
            case .inactive:
                self = newValue.isEmpty ? .inactive : .checking(newValue)
            case .checking:
                self = newValue.isEmpty ? .inactive : .checking(newValue)
            case .ready(var ready):
                ready.visibleActions = newValue
                self = newValue.isEmpty ? .inactive : .ready(ready)
            case .ejecting(var batch):
                batch.visibleActions = newValue
                self = newValue.isEmpty ? .inactive : .ejecting(batch)
            case .completed(var summary):
                summary.visibleActions = newValue
                self = newValue.isEmpty ? .inactive : .completed(summary)
            }
        }
    }

    var inventory: DiskInventoryState {
        get {
            switch self {
            case .inactive, .checking:
                return .checking
            case .ready(let ready):
                return ready.inventory
            case .ejecting(let batch):
                return batch.inventory
            case .completed(let summary):
                return summary.inventory
            }
        }
        set {
            switch self {
            case .inactive:
                break
            case .checking(let actions):
                self = .ready(ReadyEjectState(visibleActions: actions, inventory: newValue))
            case .ready(var ready):
                ready.inventory = newValue
                self = .ready(ready)
            case .ejecting(var batch):
                batch.inventory = newValue
                self = .ejecting(batch)
            case .completed(var summary):
                summary.inventory = newValue
                self = .completed(summary)
            }
        }
    }
}

enum KeyImage: String, Sendable, Equatable {
    case normal = "key-icon"
    case ejecting
}

enum KeyFeedback: Sendable, Equatable {
    case ok
    case alert
}

struct KeyPresentation: Sendable, Equatable {
    let title: String?
    let image: KeyImage
    let feedback: KeyFeedback?
}

enum EjectPresentation {
    static func make(
        state: EjectCoordinatorState,
        settings: EjectActionSettings,
        feedback: KeyFeedback? = nil
    ) -> KeyPresentation {
        let title = settings.showTitle ? visibleTitle(for: state) : nil
        let image: KeyImage
        if case .ejecting = state {
            image = .ejecting
        } else {
            image = .normal
        }
        return KeyPresentation(title: title, image: image, feedback: feedback)
    }

    static func errorTitle(result: BatchEjectResult, showTitle: Bool) -> String? {
        guard showTitle else { return nil }
        return failureTitle(
            total: result.totalCount,
            succeeded: result.successCount,
            categories: result.results.compactMap { $0.success ? nil : $0.errorCategory }
        )
    }

    private static func visibleTitle(for state: EjectCoordinatorState) -> String {
        switch state {
        case .inactive, .checking:
            return "Checking…"
        case .ready(let ready):
            return inventoryTitle(ready.inventory)
        case .ejecting(let batch):
            return activeTitle(batch)
        case .completed(let summary):
            return completedTitle(summary)
        }
    }

    private static func inventoryTitle(_ inventory: DiskInventoryState) -> String {
        switch inventory {
        case .checking:
            return "Checking…"
        case .unavailable:
            return "Failed"
        case .available(let count):
            return count > 0 ? "\(count) Disk\(count == 1 ? "" : "s")" : "No Disks"
        }
    }

    private static func activeTitle(_ batch: BatchEjectState) -> String {
        let states = Array(batch.devices.values)
        if let failure = states.compactMap({ state -> DeviceEjectFailure? in
            if case .failed(let failure) = state { return failure }
            return nil
        }).first {
            return categoryTitle(failure.category)
        }
        if states.contains(where: { if case .timedOut = $0 { true } else { false } }) {
            return "Timeout"
        }
        if states.contains(where: { if case .ejecting(.attention) = $0 { true } else { false } }) ||
            states.contains(where: { if case .unmounting(.attention) = $0 { true } else { false } }) {
            return "Check Disk"
        }
        if states.contains(where: { if case .ejecting(.slow) = $0 { true } else { false } }) ||
            states.contains(where: { if case .unmounting(.slow) = $0 { true } else { false } }) {
            return "Working…"
        }
        return "Ejecting…"
    }

    private static func completedTitle(_ summary: BatchEjectSummary) -> String {
        if summary.hadNoDisks { return "No Disks" }
        if summary.allDevicesSafeToRemove { return "Ejected!" }
        if summary.hasUnconfirmedDevice { return "Check Disk" }

        let categories = summary.devices.values.compactMap { state -> DiskErrorCategory? in
            if case .failed(let failure) = state { return failure.category }
            return nil
        }
        return failureTitle(
            total: summary.totalVolumeCount,
            succeeded: summary.successfulVolumeCount,
            categories: categories
        )
    }

    private static func failureTitle(total: Int, succeeded: Int, categories: [DiskErrorCategory]) -> String {
        if !categories.isEmpty && categories.allSatisfy({ $0 == .permission }) {
            return "Grant\nAccess"
        }
        if succeeded == 0 {
            if total == 1, let category = categories.first {
                return categoryTitle(category)
            }
            return total > 1 ? "All Failed" : "Failed"
        }
        return "\(max(0, total - succeeded)) of \(total)\nFailed"
    }

    private static func categoryTitle(_ category: DiskErrorCategory) -> String {
        switch category {
        case .busy:
            return "In Use"
        case .timeout:
            return "Timeout"
        case .permission:
            return "Grant\nAccess"
        default:
            return "Failed"
        }
    }
}
