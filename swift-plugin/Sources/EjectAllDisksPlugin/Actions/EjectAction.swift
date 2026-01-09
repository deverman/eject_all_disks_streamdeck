//
//  EjectAction.swift
//  EjectAllDisksPlugin
//
//  Stream Deck action for ejecting all external disks.
//  Uses static SVG resources and SwiftDiskArbitration for disk operations.
//

import Foundation
import StreamDeck
import SwiftDiskArbitration
import os.log

/// Logger for action events
private let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")

/// Settings for the Eject action
struct EjectActionSettings: Codable, Hashable, Sendable {
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

    // MARK: - Static Image Paths

    private enum Images {
        static let normal = "imgs/actions/eject/state"
        static let ejecting = "imgs/actions/eject/ejecting"
        static let success = "imgs/actions/eject/success"
        static let error = "imgs/actions/eject/error"
    }

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
        log.info("Action appeared on device \(device)")

        let showTitle = payload.settings?.showTitle ?? true
        updateDisplay(showTitle: showTitle)
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action disappeared from device \(device)")
    }

    // MARK: - Settings Events

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        let showTitle = payload.settings.showTitle
        updateDisplay(showTitle: showTitle)
        log.debug("Settings updated: showTitle=\(showTitle)")
    }

    func didReceiveGlobalSettings() {
        // Update title when global disk count changes
        let showTitle = true // Default, actual value comes from settings
        updateDisplay(showTitle: showTitle)
    }

    // MARK: - Key Events

    func keyDown(device: String, payload: KeyEvent<Settings>) {
        log.info("Key down - starting eject operation")

        // Prevent multiple simultaneous eject operations
        guard !isEjecting else {
            log.warning("Eject already in progress, ignoring key press")
            return
        }

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

        // Show ejecting state
        setImage(to: Images.ejecting)
        setTitle(showTitle ? "Ejecting..." : "")

        do {
            let session = try DiskSession()
            let volumes = await session.enumerateEjectableVolumes()

            if volumes.isEmpty {
                log.info("No disks to eject")
                setImage(to: Images.success)
                setTitle(showTitle ? "No Disks" : "")
                showOk()
            } else {
                log.info("Ejecting \(volumes.count) volume(s)")
                let result = await session.ejectAll(volumes, options: .default)

                logResults(result)

                if result.failedCount == 0 {
                    setImage(to: Images.success)
                    setTitle(showTitle ? "Ejected!" : "")
                    showOk()
                } else {
                    setImage(to: Images.error)
                    setTitle(showTitle ? "Error" : "")
                    showAlert()
                }
            }
        } catch {
            log.error("Failed to create DiskSession: \(error.localizedDescription)")
            setImage(to: Images.error)
            setTitle(showTitle ? "Failed" : "")
            showAlert()
        }

        // Reset display after delay
        try? await Task.sleep(for: .seconds(2))

        isEjecting = false
        updateDisplay(showTitle: showTitle)
        log.info("Display reset to normal state")
    }

    // MARK: - Display Updates

    /// Updates the display with current state
    private func updateDisplay(showTitle: Bool) {
        setImage(to: Images.normal)

        if showTitle {
            if diskCount > 0 {
                setTitle("\(diskCount) Disk\(diskCount == 1 ? "" : "s")")
            } else {
                setTitle("Eject All\nDisks")
            }
        } else {
            setTitle("")
        }
    }

    /// Logs eject results for debugging
    private func logResults(_ result: BatchEjectResult) {
        log.info("Eject completed: \(result.successCount)/\(result.totalCount) succeeded")
        for singleResult in result.results {
            if singleResult.success {
                log.debug("  [OK] \(singleResult.volumeName)")
            } else {
                log.error("  [FAIL] \(singleResult.volumeName): \(singleResult.errorMessage ?? "Unknown error")")
            }
        }
    }
}
