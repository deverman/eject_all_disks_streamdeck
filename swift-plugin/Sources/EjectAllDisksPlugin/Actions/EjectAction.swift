//
//  EjectAction.swift
//  EjectAllDisksPlugin
//
//  Stream Deck action for ejecting all external disks.
//  Handles key events, icon updates, and eject operations.
//

import Foundation
import StreamDeck
import SwiftDiskArbitration
import os.log

/// Logger for action events
private let actionLog = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")

/// Settings for the Eject action
struct EjectActionSettings: Codable, Hashable {
    /// Whether to show the title on the button
    var showTitle: Bool = true
}

/// Stream Deck action for ejecting all external disks
struct EjectAction: KeyAction {

    // MARK: - Action Metadata

    typealias Settings = EjectActionSettings

    static var name: String = "Eject All Disks"
    static var uuid: String = "org.deverman.ejectalldisks.eject"
    static var icon: String = "imgs/actions/eject/icon"
    static var propertyInspectorPath: String? = "ui/eject-all-disks.html"

    static var states: [PluginActionState] = [
        PluginActionState(
            image: "imgs/actions/eject/state",
            titleAlignment: .middle
        )
    ]

    // MARK: - Instance Properties

    var context: String
    var coordinates: StreamDeck.Coordinates?

    /// Access to global disk count
    @GlobalSetting(\.diskCount) var diskCount: Int

    /// Access to global ejecting state
    @GlobalSetting(\.isEjecting) var isEjecting: Bool

    // MARK: - Initialization

    init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        actionLog.info("Action appeared on device \(device)")

        // Set initial title based on settings
        let showTitle = payload.settings?.showTitle ?? true
        setTitle(showTitle ? "Eject All\nDisks" : "")

        // Update icon with current disk count
        updateIconWithCount(diskCount)
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        actionLog.info("Action disappeared from device \(device)")
    }

    // MARK: - Settings Events

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        let showTitle = payload.settings.showTitle
        setTitle(showTitle ? "Eject All\nDisks" : "")
        actionLog.debug("Settings updated: showTitle=\(showTitle)")
    }

    func didReceiveGlobalSettings() {
        // Update icon when global disk count changes
        updateIconWithCount(diskCount)
    }

    // MARK: - Key Events

    func keyDown(device: String, payload: KeyEvent<Settings>) {
        actionLog.info("Key down - starting eject operation")

        // Prevent multiple simultaneous eject operations
        guard !isEjecting else {
            actionLog.warning("Eject already in progress, ignoring key press")
            return
        }

        // Get current settings
        let showTitle = payload.settings.showTitle

        // Start async eject operation
        Task {
            await performEject(showTitle: showTitle)
        }
    }

    func keyUp(device: String, payload: KeyEvent<Settings>) {
        // No action needed on key up
    }

    // MARK: - Eject Operation

    /// Performs the disk eject operation
    @MainActor
    private func performEject(showTitle: Bool) async {
        isEjecting = true

        // Show ejecting icon
        setImage(to: IconGenerator.createEjectingSvg())
        setTitle(showTitle ? "Ejecting..." : "")

        do {
            // Create a session for the eject operation
            let session = try DiskSession()
            let volumes = await session.enumerateEjectableVolumes()

            if volumes.isEmpty {
                // No disks to eject
                actionLog.info("No disks to eject")
                setImage(to: IconGenerator.createSuccessSvg())
                setTitle(showTitle ? "No Disks" : "")
                showOk()
            } else {
                // Perform the eject operation
                actionLog.info("Ejecting \(volumes.count) volume(s)")
                let result = await session.ejectAll(volumes, options: .default)

                // Log results
                actionLog.info("Eject completed: \(result.successCount)/\(result.totalCount) succeeded")
                for singleResult in result.results {
                    if singleResult.success {
                        actionLog.debug("  [OK] \(singleResult.volumeName)")
                    } else {
                        actionLog.error("  [FAIL] \(singleResult.volumeName): \(singleResult.errorMessage ?? "Unknown error")")
                    }
                }

                // Show result
                if result.failedCount == 0 {
                    // All succeeded
                    setImage(to: IconGenerator.createSuccessSvg())
                    setTitle(showTitle ? "Ejected!" : "")
                    showOk()
                } else if result.successCount > 0 {
                    // Partial success
                    setImage(to: IconGenerator.createErrorSvg())
                    setTitle(showTitle ? "Partial" : "")
                    showAlert()
                } else {
                    // All failed
                    setImage(to: IconGenerator.createErrorSvg())
                    setTitle(showTitle ? "Error!" : "")
                    showAlert()
                }
            }
        } catch {
            // Session creation failed
            actionLog.error("Failed to create DiskSession: \(error.localizedDescription)")
            setImage(to: IconGenerator.createErrorSvg())
            setTitle(showTitle ? "Failed!" : "")
            showAlert()
        }

        // Reset display after delay
        try? await Task.sleep(for: .seconds(2))

        // Reset to normal state
        isEjecting = false
        setTitle(showTitle ? "Eject All\nDisks" : "")
        updateIconWithCount(diskCount)

        actionLog.info("Display reset to normal state")
    }

    // MARK: - Icon Updates

    /// Updates the button icon with the current disk count
    private func updateIconWithCount(_ count: Int) {
        let svg = IconGenerator.createNormalSvg(count: count)
        setImage(to: svg)
    }
}

// MARK: - Property Inspector Communication

extension EjectAction {

    func sendToPlugin(context: String, payload: [String: Any]) {
        actionLog.debug("Received message from Property Inspector: \(payload)")

        // Handle setup status check
        if payload["checkSetupStatus"] != nil {
            // With native Swift plugin, sudo configuration is not typically needed
            // as the plugin runs with user permissions
            let response: [String: Any] = [
                "setupStatus": [
                    "configured": true,
                    "setupCommand": "No setup required for native plugin"
                ]
            ]
            sendToPropertyInspector(payload: response)
            actionLog.info("Sent setup status to Property Inspector")
        }
    }
}
