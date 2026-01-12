//
//  EjectAllDisksPlugin.swift
//  EjectAllDisksPlugin
//
//  Native Swift Stream Deck plugin for ejecting all external disks.
//  Uses SwiftDiskArbitration for direct, fast disk operations.
//

import Foundation
import StreamDeck
import SwiftDiskArbitration
import OSLog

/// Logger for plugin events
fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "plugin")
fileprivate let debugLoggingEnabled = ProcessInfo.processInfo.environment["EJECT_ALL_DISKS_DEBUG"] == "1"

/// Global settings shared across all actions
extension GlobalSettings {
    /// Whether an eject operation is currently in progress
    @Entry var isEjecting: Bool = false
}

/// Main plugin class for Eject All Disks
@main
class EjectAllDisksPlugin: Plugin {

    // MARK: - Plugin Metadata

    static var name: String = "Eject All Disks"
    static var description: String = "Ejects all external hard disks"
    static var category: String? = "Eject All Disks"
    static var categoryIcon: String? = "imgs/plugin/category-icon"
    static var author: String = "Brent Deverman"
    static var icon: String = "imgs/plugin/marketplace"
    static var version: String = "3.0.0"

    static var os: [PluginOS] = [.macOS("13")]
    static var software: PluginSoftware = .minimumVersion("6.4")

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
        if debugLoggingEnabled {
            log.debug("EjectAllDisksPlugin initialized")
        }
    }
}
