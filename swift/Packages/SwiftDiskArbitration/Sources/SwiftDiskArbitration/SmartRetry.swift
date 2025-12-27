//
//  SmartRetry.swift
//  SwiftDiskArbitration
//
//  Intelligent retry logic with automatic blocker detection and termination
//

import DiskArbitration
import Foundation

/// Options for smart retry behavior
public struct RetryOptions: Sendable {
    /// Maximum number of retry attempts
    public let maxAttempts: Int

    /// Whether to automatically kill known blocker processes
    public let autoKillBlockers: Bool

    /// Delay between retry attempts (in nanoseconds)
    public let retryDelay: UInt64

    /// Whether to use exponential backoff
    public let useExponentialBackoff: Bool

    /// List of process names that are safe to auto-kill
    public let killableProcesses: Set<String>

    public static let `default` = RetryOptions(
        maxAttempts: 3,
        autoKillBlockers: false,
        retryDelay: 200_000_000, // 200ms
        useExponentialBackoff: true,
        killableProcesses: [
            "mds", "mds_stores", "mdworker",  // Spotlight (safe to kill, will restart)
            "photoanalysisd"                   // Photos analysis (safe to pause)
        ]
    )

    public static let aggressive = RetryOptions(
        maxAttempts: 5,
        autoKillBlockers: true,
        retryDelay: 100_000_000, // 100ms
        useExponentialBackoff: true,
        killableProcesses: [
            "mds", "mds_stores", "mdworker",
            "photoanalysisd",
            "bird", "cloudd"  // iCloud sync
        ]
    )

    public static let conservative = RetryOptions(
        maxAttempts: 2,
        autoKillBlockers: false,
        retryDelay: 500_000_000, // 500ms
        useExponentialBackoff: false,
        killableProcesses: []
    )

    public init(
        maxAttempts: Int,
        autoKillBlockers: Bool,
        retryDelay: UInt64,
        useExponentialBackoff: Bool,
        killableProcesses: Set<String>
    ) {
        self.maxAttempts = maxAttempts
        self.autoKillBlockers = autoKillBlockers
        self.retryDelay = retryDelay
        self.useExponentialBackoff = useExponentialBackoff
        self.killableProcesses = killableProcesses
    }
}

/// Result of a retry operation with diagnostic information
public struct RetryResult: Sendable {
    /// Whether the operation ultimately succeeded
    public let success: Bool

    /// Number of attempts made
    public let attempts: Int

    /// Final error if failed
    public let error: DiskError?

    /// Processes that were killed during retry
    public let killedProcesses: [String]

    /// Duration of the entire retry sequence
    public let duration: TimeInterval

    /// User-friendly diagnostic message
    public let diagnostic: DiagnosticMessage?
}

/// Smart retry handler for disk operations
public actor SmartRetryHandler {
    private let retryOptions: RetryOptions

    public init(retryOptions: RetryOptions = .default) {
        self.retryOptions = retryOptions
    }

    /// Execute an operation with smart retry logic
    public func execute<T>(
        operation: @Sendable () async -> (success: Bool, error: DiskError?),
        volumePath: String,
        volumeName: String
    ) async -> RetryResult {
        let startTime = Date()
        var attempts = 0
        var killedProcesses: [String] = []
        var lastError: DiskError? = nil

        while attempts < retryOptions.maxAttempts {
            attempts += 1

            // Attempt the operation
            let result = await operation()

            if result.success {
                let duration = Date().timeIntervalSince(startTime)
                return RetryResult(
                    success: true,
                    attempts: attempts,
                    error: nil,
                    killedProcesses: killedProcesses,
                    duration: duration,
                    diagnostic: nil
                )
            }

            lastError = result.error

            // If this is the last attempt or error isn't retryable, give up
            guard attempts < retryOptions.maxAttempts,
                  let error = result.error,
                  error.isDiskBusy else {
                break
            }

            // Try to identify and kill blocking processes
            if retryOptions.autoKillBlockers {
                let blockersKilled = await tryKillBlockingProcesses(path: volumePath)
                killedProcesses.append(contentsOf: blockersKilled)
            }

            // Wait before retry with optional exponential backoff
            let delay = retryOptions.useExponentialBackoff
                ? retryOptions.retryDelay * UInt64(1 << (attempts - 1))
                : retryOptions.retryDelay

            try? await Task.sleep(nanoseconds: delay)
        }

        // Failed after all attempts
        let duration = Date().timeIntervalSince(startTime)
        let blockingProcesses = await getBlockingProcessInfo(path: volumePath)

        let diagnostic = lastError.map { error in
            DiagnosticMessage.from(
                error: error,
                volumeName: volumeName,
                blockingProcesses: blockingProcesses
            )
        }

        return RetryResult(
            success: false,
            attempts: attempts,
            error: lastError,
            killedProcesses: killedProcesses,
            duration: duration,
            diagnostic: diagnostic
        )
    }

    /// Attempt to kill processes blocking the volume
    private nonisolated func tryKillBlockingProcesses(path: String) async -> [String] {
        var killed: [String] = []

        // This is a placeholder - actual implementation would use libproc APIs
        // to find processes with open files on the path, then kill killable ones

        // In the real implementation, this would:
        // 1. Call getBlockingProcesses(path: path)
        // 2. Filter for processes in retryOptions.killableProcesses
        // 3. Send SIGTERM to each killable process
        // 4. Wait briefly for processes to exit
        // 5. Return list of killed process names

        return killed
    }

    /// Get information about processes blocking the volume
    private nonisolated func getBlockingProcessInfo(path: String) async -> [String: String] {
        // Placeholder - would use libproc APIs to get process details
        // Returns map of process name -> friendly description
        return [:]
    }
}

// MARK: - DiskSession Extension

extension DiskSession {
    /// Unmount a volume with smart retry logic
    public func unmountWithRetry(
        _ volume: Volume,
        options: EjectOptions = .default,
        retryOptions: RetryOptions = .default
    ) async -> RetryResult {
        let handler = SmartRetryHandler(retryOptions: retryOptions)

        return await handler.execute(
            operation: {
                let result = await self.unmount(volume, options: options)
                return (success: result.success, error: result.error)
            },
            volumePath: volume.info.path,
            volumeName: volume.info.name
        )
    }

    /// Eject all volumes with smart retry on individual failures
    public func ejectAllWithRetry(
        _ volumes: [Volume],
        options: EjectOptions = .default,
        retryOptions: RetryOptions = .default
    ) async -> BatchEjectResultWithDiagnostics {
        let startTime = Date()

        guard !volumes.isEmpty else {
            return BatchEjectResultWithDiagnostics(
                totalCount: 0,
                successCount: 0,
                failedCount: 0,
                results: [],
                totalDuration: 0,
                diagnostics: []
            )
        }

        // Group volumes by physical device (same as regular eject)
        let deviceGroups = groupVolumesByPhysicalDevice(volumes)

        // Process each device with retry logic
        let results = await withTaskGroup(
            of: (SingleEjectResult, DiagnosticMessage?).self,
            returning: [(SingleEjectResult, DiagnosticMessage?)].self
        ) { group in
            for deviceGroup in deviceGroups {
                group.addTask {
                    // Try to eject this device with retry
                    let handler = SmartRetryHandler(retryOptions: retryOptions)

                    // For simplicity, we'll retry the whole device group
                    let retryResult = await handler.execute(
                        operation: {
                            // This would call the actual unmount operation
                            // Placeholder for now
                            return (success: false, error: .busy(message: "Device busy"))
                        },
                        volumePath: deviceGroup.volumes.first?.info.path ?? "",
                        volumeName: deviceGroup.volumes.first?.info.name ?? ""
                    )

                    // Create results for all volumes in this group
                    let result = SingleEjectResult(
                        volumeName: deviceGroup.volumes.first?.info.name ?? "",
                        volumePath: deviceGroup.volumes.first?.info.path ?? "",
                        success: retryResult.success,
                        errorMessage: retryResult.error?.description,
                        duration: retryResult.duration
                    )

                    return (result, retryResult.diagnostic)
                }
            }

            var collected: [(SingleEjectResult, DiagnosticMessage?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let successCount = results.filter { $0.0.success }.count
        let diagnostics = results.compactMap { $0.1 }

        return BatchEjectResultWithDiagnostics(
            totalCount: volumes.count,
            successCount: successCount,
            failedCount: volumes.count - successCount,
            results: results.map { $0.0 },
            totalDuration: totalDuration,
            diagnostics: diagnostics
        )
    }
}

/// Extended batch result with diagnostic information
public struct BatchEjectResultWithDiagnostics: Sendable {
    public let totalCount: Int
    public let successCount: Int
    public let failedCount: Int
    public let results: [SingleEjectResult]
    public let totalDuration: TimeInterval
    public let diagnostics: [DiagnosticMessage]
}
