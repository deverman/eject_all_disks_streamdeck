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
import OSLog

/// Logger for action events
fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")

/// Settings for the Eject action
struct EjectActionSettings: Codable, Hashable, Sendable {
    var showTitle: Bool = true
}

/// Stream Deck action for ejecting all external disks
class EjectAction: KeyAction {

    // MARK: - Action Metadata

    typealias Settings = EjectActionSettings

    static var name: String = "Eject All Disks"
    static var uuid: String = "org.deverman.ejectalldisks.eject"
    static var icon: String = "imgs/actions/eject/icon"
    static var propertyInspectorPath: String? = "ui/eject-all-disks.html"

    static var states: [PluginActionState]? = [
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

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action appeared on device \(device)")

        let showTitle = payload.settings.showTitle
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
        log.debug("Global settings changed, disk count: \(self.diskCount)")
        updateDisplay(showTitle: true)
    }

    // MARK: - Key Events

    func keyUp(device: String, payload: KeyEvent<Settings>, longPress: Bool) {
        if longPress { return }

        log.info("Key up - starting eject operation")

        // Prevent multiple simultaneous eject operations
        guard !isEjecting else {
            log.warning("Eject already in progress, ignoring key press")
            return
        }

        let showTitle = payload.settings.showTitle

        // Start async eject operation
        Task { @MainActor in
            await performEject(showTitle: showTitle)
        }
    }

    // MARK: - Eject Operation

    /// Performs the disk eject operation
    @MainActor
    private func performEject(showTitle: Bool) async {
        isEjecting = true

        // Show ejecting state
        setImage(toImage: "ejecting", withExtension: "svg", subdirectory: "imgs/actions/eject")
        setTitle(to: showTitle ? "Ejecting..." : nil, target: nil, state: nil)

        do {
            let session = try DiskSession()
            let volumes = await session.enumerateEjectableVolumes()

            if volumes.isEmpty {
                log.info("No disks to eject")
                setImage(toImage: "success", withExtension: "svg", subdirectory: "imgs/actions/eject")
                setTitle(to: showTitle ? "No Disks" : nil, target: nil, state: nil)
                showOk()
            } else {
                log.info("Ejecting \(volumes.count) volume(s)")
                let result = await session.ejectAll(volumes, options: .default)

                logResults(result)

                if result.failedCount == 0 {
                    setImage(toImage: "success", withExtension: "svg", subdirectory: "imgs/actions/eject")
                    setTitle(to: showTitle ? "Ejected!" : nil, target: nil, state: nil)
                    showOk()
                } else {
                    setImage(toImage: "error", withExtension: "svg", subdirectory: "imgs/actions/eject")
                    setTitle(to: showTitle ? "Error" : nil, target: nil, state: nil)
                    showAlert()
                }
            }
        } catch {
            log.error("Failed to create DiskSession: \(error.localizedDescription)")
            setImage(toImage: "error", withExtension: "svg", subdirectory: "imgs/actions/eject")
            setTitle(to: showTitle ? "Failed" : nil, target: nil, state: nil)
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
        setImage(toImage: "state", withExtension: "svg", subdirectory: "imgs/actions/eject")

        if showTitle {
            if diskCount > 0 {
                setTitle(to: "\(diskCount) Disk\(diskCount == 1 ? "" : "s")", target: nil, state: nil)
            } else {
                setTitle(to: "Eject All\nDisks", target: nil, state: nil)
            }
        } else {
            setTitle(to: nil, target: nil, state: nil)
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
