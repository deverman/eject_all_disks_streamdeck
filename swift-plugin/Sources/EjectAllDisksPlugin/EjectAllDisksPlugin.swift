//
//  EjectAllDisksPlugin.swift
//  EjectAllDisksPlugin
//
//  Main plugin entry point for the Eject All Disks Stream Deck plugin.
//  Uses the StreamDeckPlugin framework for native Swift plugin development.
//

import Foundation
import StreamDeck
import SwiftDiskArbitration
import os.log

/// Logger for plugin events
let pluginLog = Logger(subsystem: "org.deverman.ejectalldisks", category: "plugin")

/// Global settings shared across all actions
extension GlobalSettings {
    /// Current count of ejectable external disks
    @Entry var diskCount: Int = 0

    /// Whether an eject operation is currently in progress
    @Entry var isEjecting: Bool = false

    /// Last update timestamp for disk count
    @Entry var lastUpdate: Date = Date.distantPast
}

/// Main plugin class for Eject All Disks
@main
class EjectAllDisksPlugin: Plugin {

    // MARK: - Plugin Metadata

    static var name: String = "Eject All Disks"
    static var description: String = "Ejects all external hard disks with a single button press"
    static var author: String = "Brent Deverman"
    static var icon: String = "imgs/plugin/marketplace"
    static var version: String = "3.0.0"
    static var url: URL? = URL(string: "https://github.com/deverman/eject_all_disks_streamdeck")

    static var os: [PluginOS] = [
        PluginOS(platform: .mac, minimumVersion: "12")
    ]

    // MARK: - Actions

    @ActionBuilder
    static var actions: [any Action.Type] {
        EjectAction.self
    }

    // MARK: - Disk Monitoring

    /// Timer for periodic disk count updates
    private var monitoringTimer: Timer?

    /// Disk session for monitoring (separate from eject operations)
    private let monitorSession: DiskSession?

    // MARK: - Initialization

    required init() {
        // Initialize monitoring session
        do {
            self.monitorSession = try DiskSession()
            pluginLog.info("EjectAllDisksPlugin initialized successfully")
        } catch {
            pluginLog.error("Failed to create DiskSession: \(error.localizedDescription)")
            self.monitorSession = nil
        }

        // Start disk monitoring
        startDiskMonitoring()
    }

    deinit {
        stopDiskMonitoring()
    }

    // MARK: - Monitoring

    /// Starts periodic monitoring of disk count
    private func startDiskMonitoring() {
        // Initial update
        Task {
            await updateDiskCount()
        }

        // Schedule periodic updates every 3 seconds
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task {
                await self?.updateDiskCount()
            }
        }

        pluginLog.info("Disk monitoring started (3 second interval)")
    }

    /// Stops disk monitoring
    private func stopDiskMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        pluginLog.info("Disk monitoring stopped")
    }

    /// Updates the global disk count
    @MainActor
    private func updateDiskCount() async {
        guard let session = monitorSession else {
            pluginLog.warning("No monitoring session available")
            return
        }

        let count = await session.ejectableVolumeCount()
        let currentCount = GlobalSettings.shared[\.diskCount]

        if count != currentCount {
            GlobalSettings.shared[\.diskCount] = count
            GlobalSettings.shared[\.lastUpdate] = Date()
            pluginLog.debug("Disk count updated: \(currentCount) -> \(count)")
        }
    }
}
