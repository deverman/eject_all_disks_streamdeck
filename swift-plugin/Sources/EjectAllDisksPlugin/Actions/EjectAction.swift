import Foundation
import OSLog
// The reviewed StreamDeck dependency predates complete Sendable annotations.
// Repository-owned mutable state never crosses this narrow unsafe boundary.
@unsafe @preconcurrency import StreamDeck
import SwiftDiskArbitration

private let actionLog = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")

struct EjectActionSettings: Codable, Hashable, Sendable {
    var showTitle: Bool = true

    init(showTitle: Bool = true) {
        self.showTitle = showTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showTitle = try container.decodeIfPresent(Bool.self, forKey: .showTitle) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case showTitle
    }
}

/// Nonisolated Stream Deck protocol edge. It owns no mutable business state and
/// starts no tasks; every callback synchronously submits an immutable snapshot
/// to the process-wide ordered ingress.
final class EjectAction: KeyAction {
    typealias Settings = EjectActionSettings

    static let name = "SafeEject All"
    static let uuid = "org.deverman.ejectalldisks.eject"
    static let icon = "imgs/actions/eject/icon"
    static let propertyInspectorPath: String? = "ui/eject-all-disks.html"
    static let states: [PluginActionState]? = [
        PluginActionState(image: "imgs/actions/eject/icon", titleAlignment: .middle)
    ]

    let context: String
    let coordinates: StreamDeck.Coordinates?
    private let instanceID: ActionInstanceID
    private let subscriptionID: SubscriptionID
    private let ingress: EventIngress

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
        self.instanceID = ActionInstanceID()
        self.subscriptionID = SubscriptionID()
        self.ingress = PluginRuntime.shared.ingress
    }

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        actionLog.info("Action appeared")
        ingress.submit(.actionAppeared(ActionAppearance(
            context: context,
            instanceID: instanceID,
            subscriptionID: subscriptionID,
            device: device,
            settings: payload.settings
        )))
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        actionLog.info("Action disappeared")
        ingress.submit(.actionDisappeared(ActionDisappearance(
            context: context,
            instanceID: instanceID,
            subscriptionID: subscriptionID
        )))
    }

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        ingress.submit(.settingsChanged(ActionSettingsSnapshot(
            context: context,
            instanceID: instanceID,
            settings: payload.settings
        )))
    }

    func keyUp(device: String, payload: KeyEvent<Settings>, longPress: Bool) {
        actionLog.info("Key release received; longPress=\(longPress, privacy: .public)")
        ingress.submit(.keyReleased(ActionKeyRelease(
            context: context,
            instanceID: instanceID,
            longPress: longPress,
            settings: payload.settings
        )))
    }

    /// Compatibility shim for existing focused formatting tests. Presentation
    /// policy itself belongs to the pure state/presentation layer.
    static func formatErrorTitle(result: BatchEjectResult, showTitle: Bool) -> String? {
        EjectPresentation.errorTitle(result: result, showTitle: showTitle)
    }
}
