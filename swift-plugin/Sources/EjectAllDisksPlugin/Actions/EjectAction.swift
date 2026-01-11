//
//  EjectAction.swift
//  EjectAllDisksPlugin
//
//  Stream Deck action for ejecting all external disks.
//  Uses static SVG resources and SwiftDiskArbitration for disk operations.
//
// ============================================================================
// SWIFT BEGINNER'S GUIDE TO THIS FILE
// ============================================================================
//
// WHAT THIS FILE DOES:
// --------------------
// Implements the Stream Deck button that ejects all external drives when pressed.
// Shows the current disk count on the button and updates it every 3 seconds.
//
// KEY CONCEPTS:
// -------------
//
// 1. KeyAction PROTOCOL
//    Stream Deck plugins define "actions" (buttons). Each action must:
//    - Have metadata (name, icon, UUID)
//    - Handle lifecycle events (willAppear, willDisappear)
//    - Handle key events (keyUp, keyDown)
//
// 2. @GlobalSetting PROPERTY WRAPPER
//    The `@GlobalSetting(\.isEjecting)` syntax creates a shared variable.
//    All instances of EjectAction see the same `isEjecting` value.
//    This prevents multiple simultaneous eject operations.
//
// 3. DispatchSourceTimer (POLLING)
//    We poll for disk count every 3 seconds using a timer.
//    Why not use notifications? DiskArbitration notifications are unreliable.
//    Polling is simple, predictable, and "just works."
//
//    Timer lifecycle:
//      willAppear  → start timer
//      willDisappear → stop timer
//
// 4. @MainActor
//    The `@MainActor` attribute means "run this on the main thread."
//    UI updates must happen on the main thread, so performEject() uses it.
//
// 5. STATE MACHINE (Button Display)
//    The button shows different states:
//      Normal:    "2 Disks" or "Eject All Disks" (if 0)
//      Ejecting:  "Ejecting..." with spinner icon
//      Success:   "Ejected!" with checkmark icon
//      Error:     "Error" or "Failed" with error icon
//
// ============================================================================

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

    /// Access to global ejecting state
    @GlobalSetting(\.isEjecting) var isEjecting: Bool

    /// Timer for polling disk count
    private var pollingTimer: DispatchSourceTimer?

    /// Current disk count (locally tracked)
    private var diskCount: Int = -1  // Start at -1 to force first update

    /// Cached showTitle setting
    private var showTitle: Bool = true

    /// Whether this is the first appearance (needs immediate display update)
    private var needsInitialUpdate: Bool = true

    // MARK: - Initialization

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action appeared on device \(device)")

        // Cache settings - use default if not set
        self.showTitle = payload.settings.showTitle
        self.needsInitialUpdate = true
        self.diskCount = -1  // Reset to force update

        // Show immediate feedback while we fetch disk count
        setImage(toImage: "state", withExtension: "svg", subdirectory: "imgs/actions/eject")
        setTitle(to: self.showTitle ? "..." : nil, target: nil, state: nil)

        // Start polling for disk count
        startPolling(showTitle: self.showTitle)
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action disappeared from device \(device)")
        stopPolling()
    }

    // MARK: - Disk Count Polling

    private func startPolling(showTitle: Bool) {
        self.showTitle = showTitle

        // Initial update
        Task {
            await refreshDiskCount()
        }

        // Poll every 3 seconds using DispatchSourceTimer
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.refreshDiskCount()
            }
        }
        timer.resume()
        pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func refreshDiskCount() async {
        let count = await DiskSession.shared.ejectableVolumeCount()

        // Always update on first call (needsInitialUpdate) or when count changes
        if needsInitialUpdate || count != self.diskCount {
            self.diskCount = count
            self.needsInitialUpdate = false
            log.debug("Disk count updated: \(count)")
            updateDisplay(showTitle: self.showTitle)
        }
    }

    // MARK: - Settings Events

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        self.showTitle = payload.settings.showTitle
        updateDisplay(showTitle: self.showTitle)
        log.debug("Settings updated: showTitle=\(self.showTitle)")
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
                    // Show detailed error: "1 of 3 Failed" or specific error type
                    let errorTitle = formatErrorTitle(result: result, showTitle: showTitle)
                    setTitle(to: errorTitle, target: nil, state: nil)
                    showAlert()

                    // Log helpful message if permission-related
                    logPermissionHint(result: result)
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

        // Refresh disk count immediately before updating display
        self.diskCount = await DiskSession.shared.ejectableVolumeCount()
        updateDisplay(showTitle: showTitle)
        log.info("Display reset to normal state, disk count: \(self.diskCount)")
    }

    // MARK: - Display Updates

    /// Updates the display with current state
    private func updateDisplay(showTitle: Bool) {
        setImage(toImage: "state", withExtension: "svg", subdirectory: "imgs/actions/eject")

        if showTitle {
            if diskCount > 0 {
                setTitle(to: "\(diskCount) Disk\(diskCount == 1 ? "" : "s")", target: nil, state: nil)
            } else {
                // Show "No Disks" when nothing is mounted - clearer than "Eject All Disks"
                setTitle(to: "No Disks", target: nil, state: nil)
            }
        } else {
            setTitle(to: nil, target: nil, state: nil)
        }
    }

    /// Logs eject results for debugging
    /// PRIVACY: We don't log volume names as they may contain sensitive information.
    /// Volume names like "ConfidentialProject" or "ClientBackup" could reveal user data.
    private func logResults(_ result: BatchEjectResult) {
        log.info("Eject completed: \(result.successCount)/\(result.totalCount) succeeded")
        if result.failedCount > 0 {
            log.warning("\(result.failedCount) volume(s) failed to eject")
        }
    }

    /// Formats a user-friendly error title based on the eject result
    /// Shows specific information like "1 of 3 Failed" or error type hints
    private func formatErrorTitle(result: BatchEjectResult, showTitle: Bool) -> String? {
        guard showTitle else { return nil }

        // Check if all failures are permission-related (suggests missing FDA)
        let permissionErrors = result.results.filter { r in
            guard let msg = r.errorMessage else { return false }
            return msg.contains("ermission") || msg.contains("rivileged") || msg.contains("Not permitted")
        }

        // If ALL failures are permission errors, suggest granting FDA
        if permissionErrors.count == result.failedCount && result.failedCount > 0 {
            return "Grant\nAccess"
        }

        // If all failed, show count
        if result.successCount == 0 {
            if result.totalCount == 1 {
                // Single disk failed - try to show why
                if let firstResult = result.results.first,
                   let errorMsg = firstResult.errorMessage {
                    // Extract short error hint
                    if errorMsg.contains("busy") || errorMsg.contains("Busy") {
                        return "In Use"
                    } else if errorMsg.contains("timeout") || errorMsg.contains("Timeout") {
                        return "Timeout"
                    }
                }
                return "Failed"
            } else {
                return "All Failed"
            }
        }

        // Partial failure - show X of Y
        return "\(result.failedCount) of \(result.totalCount)\nFailed"
    }

    /// Logs a helpful message if failures appear to be permission-related
    /// Suggests granting Full Disk Access in System Settings
    private func logPermissionHint(result: BatchEjectResult) {
        let permissionErrors = result.results.filter { r in
            guard let msg = r.errorMessage else { return false }
            return msg.contains("ermission") || msg.contains("rivileged") || msg.contains("Not permitted")
        }

        if permissionErrors.count > 0 {
            log.error("Permission denied for \(permissionErrors.count) disk(s). Grant Full Disk Access:")
            log.error("  System Settings → Privacy & Security → Full Disk Access → Add Stream Deck")
        }
    }
}
