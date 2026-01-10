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

/// Global settings shared across all actions
extension GlobalSettings {
    /// Current count of ejectable external disks
    @Entry var diskCount: Int = 0

    /// Whether an eject operation is currently in progress
    @Entry var isEjecting: Bool = false
}

/// Main plugin class for Eject All Disks
@main
class EjectAllDisksPlugin: Plugin {

    // MARK: - Plugin Metadata

    static var name: String = "Eject All Disks"
    static var description: String = "Ejects all external hard disks"
    static var author: String = "Brent Deverman"
    static var icon: String = "imgs/plugin/marketplace"
    static var version: String = "3.0.0"

    static var os: [PluginOS] = [.macOS("13")]

    // MARK: - Actions

    @ActionBuilder
    static var actions: [any Action.Type] {
        EjectAction.self
    }

    // MARK: - Layouts

    @LayoutBuilder
    static var layouts: [Layout] { }

    // MARK: - Instance Properties

    @GlobalSetting(\.diskCount) var diskCount: Int

    // MARK: - Disk Monitoring

    private var monitoringTimer: Timer?

    // MARK: - Initialization

    required init() {
        log.info("EjectAllDisksPlugin initialized")
        startDiskMonitoring()
    }

    deinit {
        monitoringTimer?.invalidate()
    }

    // MARK: - Monitoring

    private func startDiskMonitoring() {
        // Initial update
        Task {
            await updateDiskCount()
        }

        // Update every 3 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateDiskCount()
            }
        }

        log.info("Disk monitoring started")
    }

    private func updateDiskCount() async {
        let count = await DiskSession.shared.ejectableVolumeCount()
        if count != diskCount {
            diskCount = count
            log.debug("Disk count: \(count)")
        }
    }
}
