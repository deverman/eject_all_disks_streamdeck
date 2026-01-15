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
//      Normal:    "2 Disks" or "No Disks" (if 0)
//      Ejecting:  "Ejecting..." with spinner icon
//      Success:   "Ejected!" with checkmark icon
//      Error:     "Error" or "Failed" with error icon
//
//    Note: The idle 0-disk state displays "No Disks" (matches README and tests).
//
// ============================================================================

import Foundation
import StreamDeck
import SwiftDiskArbitration
import OSLog

/// Logger for action events
fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")
fileprivate let debugLoggingEnabled = ProcessInfo.processInfo.environment["EJECT_ALL_DISKS_DEBUG"] == "1"

/// Settings for the Eject action
struct EjectActionSettings: Codable, Hashable, Sendable {
    var showTitle: Bool = true

    init(showTitle: Bool = true) {
        self.showTitle = showTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showTitle = try container.decodeIfPresent(Bool.self, forKey: .showTitle) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showTitle, forKey: .showTitle)
    }

    private enum CodingKeys: String, CodingKey {
        case showTitle
    }
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

    /// Whether polling has started (prevents double-start)
    private var pollingStarted: Bool = false

    /// Work item for delayed polling start (so it can be canceled on disappear)
    private var delayedPollingStart: DispatchWorkItem?

    // MARK: - Initialization

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        if debugLoggingEnabled {
            log.debug("Action appeared: context=\(self.context), device=\(device), isInMultiAction=\(payload.isInMultiAction)")
        }

        // Seed persisted settings on first appearance.
        //
        // SDPI Components reads directly from Stream Deck's persisted settings store.
        // When an action is first dropped onto a key, settings may be empty/missing
        // (even though Swift decoding provides defaults). Writing the decoded settings
        // ensures the Property Inspector sees explicit values (e.g., showTitle=true).
        setSettings(to: payload.settings)

        // Reset state for this appearance
        self.showTitle = payload.settings.showTitle
        self.needsInitialUpdate = true
        self.diskCount = -1
        self.pollingStarted = false
        self.delayedPollingStart?.cancel()
        self.delayedPollingStart = nil

        if debugLoggingEnabled {
            log.debug("willAppear: showTitle=\(self.showTitle)")
        }

        // Simple approach: just start polling after a 1 second delay
        // This gives Stream Deck time to fully register the action
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.pollingStarted else { return }
            self.pollingStarted = true
            if debugLoggingEnabled {
                log.debug("Starting polling after 1s delay")
            }
            self.startPolling(showTitle: self.showTitle)
        }
        self.delayedPollingStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        if debugLoggingEnabled {
            log.debug("Action disappeared from device \(device)")
        }
        delayedPollingStart?.cancel()
        delayedPollingStart = nil
        stopPolling()
    }
    
    // MARK: - Disk Count Polling

    private func startPolling(showTitle: Bool) {
        self.showTitle = showTitle
        if debugLoggingEnabled {
            log.debug("startPolling: context=\(self.context), showTitle=\(showTitle)")
        }

        // Initial update - run immediately on main actor
        Task { @MainActor in
            if debugLoggingEnabled {
                log.debug("Performing initial disk count refresh for context=\(self.context)")
            }
            await self.refreshDiskCount()
        }

        // Poll every 3 seconds using DispatchSourceTimer
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshDiskCount()
            }
        }
        timer.resume()
        pollingTimer = timer
        if debugLoggingEnabled {
            log.debug("Polling timer started for context=\(self.context)")
        }
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func refreshDiskCount() async {
        if debugLoggingEnabled {
            log.debug("refreshDiskCount called, needsInitialUpdate=\(self.needsInitialUpdate), current=\(self.diskCount)")
        }

        let count = await DiskSession.shared.ejectableVolumeCount()
        if debugLoggingEnabled {
            log.debug("DiskSession returned count: \(count)")
        }

        // Always update on first call (needsInitialUpdate) or when count changes
        if needsInitialUpdate || count != self.diskCount {
            self.diskCount = count
            self.needsInitialUpdate = false
            if debugLoggingEnabled {
                log.debug("Updating display with disk count: \(count)")
            }
            updateDisplay(showTitle: self.showTitle)
        }
    }

    // MARK: - Settings Events

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        self.showTitle = payload.settings.showTitle
        if debugLoggingEnabled {
            log.debug("didReceiveSettings: context=\(self.context), showTitle=\(self.showTitle)")
        }

        // Update display when settings change (e.g., from Property Inspector checkbox)
        updateDisplay(showTitle: self.showTitle)
    }

    // MARK: - Key Events

    func keyUp(device: String, payload: KeyEvent<Settings>, longPress: Bool) {
        if longPress { return }

        if debugLoggingEnabled {
            log.debug("Key up - starting eject operation")
        }

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
                if debugLoggingEnabled {
                    log.debug("No disks to eject")
                }
                setImage(toImage: "success", withExtension: "svg", subdirectory: "imgs/actions/eject")
                setTitle(to: showTitle ? "No Disks" : nil, target: nil, state: nil)
                showOk()
            } else {
                if debugLoggingEnabled {
                    log.debug("Ejecting \(volumes.count) volume(s)")
                }
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
        if debugLoggingEnabled {
            log.debug("Display reset to normal state, disk count: \(self.diskCount)")
        }
    }

    // MARK: - Display Updates

    /// Updates the display with current state
    private func updateDisplay(showTitle: Bool) {
        let title: String?
        if showTitle {
            if diskCount > 0 {
                title = "\(diskCount) Disk\(diskCount == 1 ? "" : "s")"
            } else {
                title = "No Disks"
            }
        } else {
            title = nil
        }

        if debugLoggingEnabled {
            log.debug("updateDisplay: context=\(self.context), title=\(title ?? "nil"), showTitle=\(showTitle)")
        }

        setImage(toImage: "state", withExtension: "svg", subdirectory: "imgs/actions/eject")
        setTitle(to: title, target: nil, state: nil)
    }

    /// Logs eject results for debugging
    /// PRIVACY: We don't log volume names as they may contain sensitive information.
    /// Volume names like "ConfidentialProject" or "ClientBackup" could reveal user data.
    private func logResults(_ result: BatchEjectResult) {
        if debugLoggingEnabled {
            log.debug("Eject completed: \(result.successCount)/\(result.totalCount) succeeded")
        }
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
