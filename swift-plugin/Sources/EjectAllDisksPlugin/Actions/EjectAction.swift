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
// Implements the Stream Deck button that ejects all external drives when
// pressed. Shows the current disk count on the button, updated the moment a
// volume mounts or unmounts.
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
// 2. DiskCountMonitor (EVENT-DRIVEN UPDATES)
//    Instead of each key polling every few seconds, one shared monitor
//    listens for NSWorkspace mount/unmount notifications and pushes the
//    disk count to every subscribed key. See DiskCountMonitor.swift.
//
//    Lifecycle:
//      willAppear    → subscribe
//      willDisappear → unsubscribe
//
// 3. @MainActor
//    The `@MainActor` attribute means "run this on the main thread."
//    UI updates must happen on the main thread, so performEject() uses it.
//
// 4. STATE MACHINE (Button Display)
//    The button shows different states:
//      Normal:    "2 Disks" or "No Disks" (if 0)
//      Ejecting:  "Ejecting..." with spinner icon
//      Success:   "Ejected!" with checkmark icon
//      Error:     "Error" or "Failed" with error icon
//
//    While an eject is in progress, count updates from the monitor are
//    ignored so they cannot overwrite the "Ejecting…"/"Ejected!" titles.
//
// ============================================================================

import Foundation
@preconcurrency import StreamDeck
import SwiftDiskArbitration
import OSLog

/// Logger for action events
fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "action")
fileprivate let debugLoggingEnabled = ProcessInfo.processInfo.environment["EJECT_ALL_DISKS_DEBUG"] == "1"

/// Process-local eject state shared across action instances.
///
/// This intentionally is not persisted in Stream Deck global settings. Persisting
/// transient state can leave the plugin stuck after Stream Deck quits or macOS
/// reboots during an eject operation.
final class EjectOperationState: @unchecked Sendable {
    private let lock = NSLock()
    private var inProgress = false

    /// Whether an eject operation is currently running.
    var isInProgress: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inProgress
    }

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !inProgress else {
            return false
        }

        inProgress = true
        return true
    }

    func finish() {
        lock.lock()
        inProgress = false
        lock.unlock()
    }
}

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

    static var name: String = "SafeEject All"
    static var uuid: String = "org.deverman.ejectalldisks.eject"
    static var icon: String = "imgs/actions/eject/icon"
    static var propertyInspectorPath: String? = "ui/eject-all-disks.html"

    static var states: [PluginActionState]? = [
        PluginActionState(
            image: "imgs/actions/eject/icon",
            titleAlignment: .middle
        )
    ]

    // MARK: - Instance Properties

    var context: String
    var coordinates: StreamDeck.Coordinates?

    /// Shared in-memory state that prevents simultaneous eject operations.
    static let ejectOperationState = EjectOperationState()

    /// Current disk count (pushed by DiskCountMonitor)
    private var diskCount: Int = 0

    /// Cached showTitle setting
    private var showTitle: Bool = true

    // MARK: - Initialization

    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    func willAppear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action appeared")
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

        self.showTitle = payload.settings.showTitle

        // Subscribe to the shared monitor. The subscriber closure fires
        // immediately with the last known count (instant first paint) and
        // again whenever a volume mounts or unmounts.
        Task { @MainActor in
            DiskCountMonitor.shared.subscribe(context: self.context) { [weak self] count in
                guard let self else { return }
                self.diskCount = count

                // Never overwrite the Ejecting…/Ejected! display mid-operation;
                // performEject triggers a refresh once it finishes.
                guard !Self.ejectOperationState.isInProgress else { return }
                self.updateDisplay(showTitle: self.showTitle)
            }
        }
    }

    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action disappeared")
        if debugLoggingEnabled {
            log.debug("Action disappeared from device \(device)")
        }
        Task { @MainActor in
            DiskCountMonitor.shared.unsubscribe(context: self.context)
        }
    }

    // MARK: - Settings Events

    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        self.showTitle = payload.settings.showTitle
        if debugLoggingEnabled {
            log.debug("didReceiveSettings: context=\(self.context), showTitle=\(self.showTitle)")
        }

        // Update display when settings change (e.g., from Property Inspector
        // checkbox) — unless an eject is showing its own state right now.
        guard !Self.ejectOperationState.isInProgress else { return }
        updateDisplay(showTitle: self.showTitle)
    }

    // MARK: - Key Events

    func keyUp(device: String, payload: KeyEvent<Settings>, longPress: Bool) {
        log.info("Key up received: longPress=\(longPress, privacy: .public)")

        if longPress {
            log.info("Ignoring long press key release")
            return
        }

        if debugLoggingEnabled {
            log.debug("Key up - starting eject operation")
        }

        // Prevent multiple simultaneous eject operations
        guard Self.ejectOperationState.begin() else {
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
        defer {
            Self.ejectOperationState.finish()
            log.info("Eject operation state cleared")
            // Publishes the fresh count to every key instance, which restores
            // the normal display now that the operation state is cleared.
            DiskCountMonitor.shared.refresh()
        }

        log.info("Eject operation started")

        // Show ejecting state
        setImage(toImage: "ejecting", withExtension: "svg", subdirectory: "imgs/actions/eject")
        setTitle(to: showTitle ? "Ejecting..." : nil, target: nil, state: nil)

        if let session = DiskSession.shared {
            let volumes = await session.enumerateEjectableVolumes()
            log.info("Enumerated ejectable volumes: count=\(volumes.count, privacy: .public)")

            if volumes.isEmpty {
                log.info("No disks to eject")
                setTitle(to: showTitle ? "No Disks" : nil, target: nil, state: nil)
                showOk()
            } else {
                if debugLoggingEnabled {
                    log.debug("Ejecting \(volumes.count) volume(s)")
                }
                let result = await session.ejectAll(volumes, options: .default)

                logResults(result)

                if result.failedCount == 0 {
                    setTitle(to: showTitle ? "Ejected!" : nil, target: nil, state: nil)
                    showOk()
                } else {
                    // Show detailed error: "1 of 3 Failed" or specific error type
                    let errorTitle = Self.formatErrorTitle(result: result, showTitle: showTitle)
                    setTitle(to: errorTitle, target: nil, state: nil)
                    showAlert()

                    // Log helpful message if permission-related
                    logPermissionHint(result: result)
                }
            }
        } else {
            log.error("DiskArbitration session unavailable")
            setTitle(to: showTitle ? "Failed" : nil, target: nil, state: nil)
            showAlert()
        }

        // Hold the result state on the key briefly before returning to normal.
        // Monitor updates are suppressed until the deferred finish() runs, so
        // nothing can overwrite this display in the meantime.
        try? await Task.sleep(for: .seconds(2))

        setImage(toImage: "icon", withExtension: "svg", subdirectory: "imgs/actions/eject")
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

        setTitle(to: title, target: nil, state: nil)
    }

    /// Logs eject results for debugging
    /// PRIVACY: We don't log volume names as they may contain sensitive information.
    /// Volume names like "ConfidentialProject" or "ClientBackup" could reveal user data.
    private func logResults(_ result: BatchEjectResult) {
        log.info(
            "Eject completed: success=\(result.successCount, privacy: .public), failed=\(result.failedCount, privacy: .public), total=\(result.totalCount, privacy: .public), duration=\(result.totalDuration, privacy: .public)s"
        )

        if result.failedCount > 0 {
            log.warning("\(result.failedCount, privacy: .public) volume(s) failed to eject")
        }

        for singleResult in result.results where !singleResult.success {
            let bsdName = singleResult.bsdName ?? "unknown"
            let category = singleResult.errorCategory?.rawValue ?? "unknown"
            log.warning(
                "Eject failure: bsd=\(bsdName, privacy: .public), category=\(category, privacy: .public), duration=\(singleResult.duration, privacy: .public)s"
            )
            if debugLoggingEnabled, let errorMessage = singleResult.errorMessage {
                log.debug("Eject failure detail: bsd=\(bsdName, privacy: .public), message=\(errorMessage, privacy: .private)")
            }
        }
    }

    /// Formats a user-friendly error title based on the eject result.
    /// Shows specific information like "1 of 3 Failed" or error type hints.
    /// Classification uses the typed `errorCategory`, never message strings.
    static func formatErrorTitle(result: BatchEjectResult, showTitle: Bool) -> String? {
        guard showTitle else { return nil }

        let failures = result.results.filter { !$0.success }

        // If ALL failures are permission errors, suggest granting Full Disk Access
        if !failures.isEmpty && failures.allSatisfy({ $0.errorCategory == .permission }) {
            return "Grant\nAccess"
        }

        // If all failed, show count
        if result.successCount == 0 {
            if result.totalCount == 1 {
                // Single disk failed - show why when we know
                switch failures.first?.errorCategory {
                case .busy:
                    return "In Use"
                case .timeout:
                    return "Timeout"
                default:
                    return "Failed"
                }
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
        let permissionFailures = result.results.filter { !$0.success && $0.errorCategory == .permission }

        if !permissionFailures.isEmpty {
            log.error("Permission denied for \(permissionFailures.count) disk(s). Grant Full Disk Access:")
            log.error("  System Settings → Privacy & Security → Full Disk Access → Add Stream Deck")
        }
    }
}
