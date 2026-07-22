import AppKit
import Foundation
import OSLog

private let monitorLog = Logger(subsystem: "org.deverman.ejectalldisks", category: "monitor")

/// Owns only AppKit observer/timer resources. Inventory values and subscribers
/// live in the coordinator state machine, so an idle monitor has no stale cache
/// to replay on the next first appearance.
@MainActor
final class DiskCountMonitor {
    static let shared = DiskCountMonitor()

    private var workspaceObservers: [NSObjectProtocol] = []
    private var fallbackTimer: DispatchSourceTimer?
    private var lifecycleEpoch: UInt64 = 0
    private let fallbackInterval: TimeInterval = 30

    init() {}

    var observerCount: Int { workspaceObservers.count }
    var hasFallbackTimer: Bool { fallbackTimer != nil }

    func start(epoch: UInt64, ingress: EventIngress) {
        guard epoch >= lifecycleEpoch else { return }
        lifecycleEpoch = epoch
        stopResources()

        let center = NSWorkspace.shared.notificationCenter
        let notificationReasons: [(Notification.Name, InventoryRefreshReason)] = [
            (NSWorkspace.didMountNotification, .workspaceNotification),
            (NSWorkspace.didUnmountNotification, .workspaceNotification),
            (NSWorkspace.didRenameVolumeNotification, .workspaceNotification),
            (NSWorkspace.didWakeNotification, .wake),
        ]

        for (name, reason) in notificationReasons {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                ingress.submit(reason == .wake ? .systemWoke : .inventoryRefreshRequested(reason))
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
            ingress.submit(.inventoryRefreshRequested(.fallback))
        }
        timer.resume()
        fallbackTimer = timer

        monitorLog.info("Disk monitoring started with event notifications and 30-second drift checks")
    }

    func stop(epoch: UInt64) {
        guard epoch >= lifecycleEpoch else { return }
        lifecycleEpoch = epoch
        stopResources()
        monitorLog.info("Disk monitoring stopped; inventory cache invalidated by coordinator")
    }

    private func stopResources() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        fallbackTimer?.cancel()
        fallbackTimer = nil
    }
}
