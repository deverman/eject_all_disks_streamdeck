//
//  EjectAllDisksPlugin.swift
//  EjectAllDisksPlugin
//
//  Native Swift Stream Deck plugin for ejecting all external disks.
//  Uses SwiftDiskArbitration for direct, fast disk operations.
//

import Foundation
// The reviewed StreamDeck dependency predates complete Sendable annotations.
@unsafe @preconcurrency import StreamDeck
import OSLog

/// Logger for plugin events
fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "plugin")
fileprivate let debugLoggingEnabled = ProcessInfo.processInfo.environment["EJECT_ALL_DISKS_DEBUG"] == "1"

/// Main plugin class for Eject All Disks
@main
class EjectAllDisksPlugin: Plugin {

    // MARK: - Plugin Metadata

    static let name: String = "SafeEject: One-Push Disk Manager"
    static let description: String = "One-push safe ejection for all your external drives. Essential utility for macOS."
    static let category: String? = "SafeEject: One-Push Disk Manager"
    static let categoryIcon: String? = "imgs/plugin/category-icon"
    static let author: String = "Brent Deverman"
    static let icon: String = "imgs/plugin/marketplace"
    // NOTE: Stream Deck manifests require exactly four segments
    // ({major}.{minor}.{patch}.{build}) — enforced by the Elgato schema.
    static let version: String = "4.0.0.0"
    static let uuid: String = "org.deverman.ejectalldisks"

    static let os: [PluginOS] = [.macOS("26")]
    static let software: PluginSoftware = .minimumVersion("6.9")

    // MARK: - Actions

    @ActionBuilder
    static var actions: [any Action.Type] {
        EjectAction.self
    }

    // MARK: - Layouts

    @LayoutBuilder
    static var layouts: [Layout] { }

    // MARK: - Initialization

    required init() {
        log.info("EjectAllDisksPlugin initialized")
        if debugLoggingEnabled {
            log.debug("EjectAllDisksPlugin initialized")
        }
    }

    // Wake handling lives in DiskCountMonitor's NSWorkspace.didWakeNotification
    // observer — the same OS-delivered channel as mount/unmount events — so the
    // Stream Deck transport's systemDidWakeUp is intentionally not observed here.
}
