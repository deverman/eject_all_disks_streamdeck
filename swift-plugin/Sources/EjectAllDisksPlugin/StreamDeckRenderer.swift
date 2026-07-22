import AppKit
import Foundation
// Unsafe only because the dependency lacks complete Sendable annotations; this
// actor serializes all transport use and validates action tokens per command.
@unsafe @preconcurrency import StreamDeck

struct RenderRequest: Sendable {
    let context: String
    let instanceID: ActionInstanceID
    let revision: UInt64
    let presentation: KeyPresentation
}

private struct TitlePayload: Encodable, Sendable {
    let title: String?
}

private struct ImagePayload: Encodable, Sendable {
    let image: String?
}

/// Serializes transport writes and validates the action token immediately before
/// every command. A stale queued render can therefore never target a context
/// that Stream Deck has reused for a newer action instance.
actor StreamDeckRenderer {
    private let activeActions: ActiveActionRegistry
    private var admission: RenderRevisionGate
    private var imageCache: [KeyImage: String] = [:]

    init(activeActions: ActiveActionRegistry) {
        self.activeActions = activeActions
        self.admission = RenderRevisionGate(activeActions: activeActions)
    }

    func render(_ request: RenderRequest) async {
        guard admission.begin(request) else { return }

        let encodedImage = await cachedImage(request.presentation.image)
        guard admission.isCurrent(request) else { return }

        await PluginCommunication.shared.sendEvent(
            .setTitle,
            context: request.context,
            payload: TitlePayload(title: request.presentation.title)
        )
        guard admission.isCurrent(request) else { return }

        await PluginCommunication.shared.sendEvent(
            .setImage,
            context: request.context,
            payload: ImagePayload(image: encodedImage)
        )
        guard admission.isCurrent(request) else { return }

        switch request.presentation.feedback {
        case .ok:
            await PluginCommunication.shared.sendEvent(
                .showOK,
                context: request.context,
                payload: Optional<String>.none
            )
        case .alert:
            await PluginCommunication.shared.sendEvent(
                .showAlert,
                context: request.context,
                payload: Optional<String>.none
            )
        case nil:
            break
        }
    }

    /// Drops the per-instance revision entry once Stream Deck removes the
    /// action, so instance churn cannot grow the gate without bound.
    func release(_ instanceID: ActionInstanceID) {
        admission.release(instanceID)
    }

    func seedSettings(
        context: String,
        instanceID: ActionInstanceID,
        settings: EjectActionSettings
    ) async {
        guard activeActions.isActive(context: context, instanceID: instanceID) else { return }
        await PluginCommunication.shared.sendEvent(
            .setSettings,
            context: context,
            payload: settings
        )
    }

    /// Encoding failures are not cached so a missing asset can recover after
    /// reinstall without restarting the plugin.
    private func cachedImage(_ image: KeyImage) async -> String? {
        if let cached = imageCache[image] { return cached }
        guard let encoded = await Self.encodedImage(image) else { return nil }
        imageCache[image] = encoded
        return encoded
    }

    @MainActor
    private static func encodedImage(_ image: KeyImage) -> String? {
        guard let url = Bundle.main.url(
            forResource: image.rawValue,
            withExtension: "svg",
            subdirectory: "imgs/actions/eject"
        ), let nsImage = NSImage(contentsOf: url) else {
            return nil
        }
        return nsImage.base64String
    }
}

struct RenderRevisionGate: Sendable {
    private let activeActions: ActiveActionRegistry
    private var latestRevision: [ActionInstanceID: UInt64] = [:]

    init(activeActions: ActiveActionRegistry) {
        self.activeActions = activeActions
    }

    mutating func begin(_ request: RenderRequest) -> Bool {
        guard activeActions.isActive(context: request.context, instanceID: request.instanceID),
            request.revision >= latestRevision[request.instanceID, default: 0]
        else { return false }
        latestRevision[request.instanceID] = request.revision
        return true
    }

    func isCurrent(_ request: RenderRequest) -> Bool {
        activeActions.isActive(context: request.context, instanceID: request.instanceID) &&
            latestRevision[request.instanceID] == request.revision
    }

    mutating func release(_ instanceID: ActionInstanceID) {
        latestRevision.removeValue(forKey: instanceID)
    }

    var trackedInstanceCount: Int { latestRevision.count }
}
