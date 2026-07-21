//
//  DiskCountMonitor.swift
//  EjectAllDisksPlugin
//
//  Shared coordinator that tracks the ejectable-disk count for every action
//  instance. One monitor serves all keys, following the shared-coordinator
//  pattern for long-lived Stream Deck key faces.
//
//  Event-driven: NSWorkspace posts didMount/didUnmount/didRenameVolume
//  notifications the moment a volume appears or disappears, so keys update
//  instantly with zero idle cost. A slow fallback poll (30s) covers the rare
//  case of a missed notification.
//

import AppKit
import Foundation
import OSLog
import SwiftDiskArbitration

fileprivate let log = Logger(subsystem: "org.deverman.ejectalldisks", category: "monitor")

/// Tracks the number of ejectable volumes and pushes changes to subscribers.
///
/// All access is confined to the main actor, matching where Stream Deck
/// display updates must happen anyway.
@MainActor
final class DiskCountMonitor {

    static let shared = DiskCountMonitor()

    /// Most recently observed count. New subscribers receive this immediately.
    private(set) var lastCount: Int = 0

    /// Subscribers keyed by action context.
    private var subscribers: [String: @MainActor (Int) -> Void] = [:]

    /// NSWorkspace notification observer tokens.
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Fallback timer in case a mount/unmount notification is missed.
    private var fallbackTimer: DispatchSourceTimer?

    /// Fallback polling interval. Notifications are the primary signal, so
    /// this only needs to catch drift, not drive responsiveness.
    private let fallbackInterval: TimeInterval = 30.0

    /// Monotonic generation counter so a stale in-flight refresh can never
    /// overwrite the result of a newer one.
    private var refreshGeneration: UInt64 = 0

    private init() {}

    // MARK: - Subscription

    /// Registers a subscriber. It immediately receives the last known count,
    /// and a fresh refresh is kicked off.
    func subscribe(context: String, onChange: @escaping @MainActor (Int) -> Void) {
        let wasEmpty = subscribers.isEmpty
        subscribers[context] = onChange

        if wasEmpty {
            start()
        }

        onChange(lastCount)
        refresh()
    }

    /// Removes a subscriber. Monitoring stops entirely when nobody is listening.
    func unsubscribe(context: String) {
        subscribers.removeValue(forKey: context)
        if subscribers.isEmpty {
            stop()
        }
    }

    // MARK: - Refresh

    /// Recomputes the count and publishes it to all subscribers.
    /// Safe to call at any time (e.g., right after an eject completes).
    func refresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        Task { @MainActor in
            let count: Int
            if let session = DiskSession.shared {
                count = await session.ejectableVolumeCount()
            } else {
                log.error("DiskArbitration session unavailable; reporting 0 disks")
                count = 0
            }

            // A newer refresh started while we were awaiting — let it win.
            guard generation == self.refreshGeneration else { return }

            self.lastCount = count
            for callback in self.subscribers.values {
                callback(count)
            }
        }
    }

    // MARK: - Lifecycle

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]

        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    DiskCountMonitor.shared.refresh()
                }
            }
            workspaceObservers.append(observer)
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + fallbackInterval,
            repeating: fallbackInterval,
            leeway: .seconds(5)
        )
        timer.setEventHandler {
            Task { @MainActor in
                DiskCountMonitor.shared.refresh()
            }
        }
        timer.resume()
        fallbackTimer = timer

        log.info("Disk monitoring started (workspace notifications + \(self.fallbackInterval, privacy: .public)s fallback)")
    }

    private func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        fallbackTimer?.cancel()
        fallbackTimer = nil

        log.info("Disk monitoring stopped (no subscribers)")
    }
}
