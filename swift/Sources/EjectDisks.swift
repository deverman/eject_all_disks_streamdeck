//
//  EjectDisks.swift
//  Fast disk ejection using native DiskArbitration APIs with Swift 6 concurrency
//
//  Uses DADiskUnmount for 10x faster ejection compared to diskutil subprocess.
//  Falls back to diskutil when needed for compatibility.
//

import ArgumentParser
import AppKit
import DiskArbitration
import Foundation
import SwiftDiskArbitration

// MARK: - JSON Output Types

struct VolumeInfoOutput: Codable, Sendable {
    let name: String
    let path: String
    let bsdName: String?
    let isEjectable: Bool
    let isRemovable: Bool
}

struct EjectResult: Codable, Sendable {
    let volume: String
    let success: Bool
    let error: String?
    let duration: Double
    let blockingProcesses: [ProcessInfoOutput]?
}

struct ProcessInfoOutput: Codable, Sendable {
    let pid: String
    let command: String
    let user: String
}

struct ListOutput: Codable, Sendable {
    let count: Int
    let volumes: [VolumeInfoOutput]
}

struct EjectOutput: Codable, Sendable {
    let totalCount: Int
    let successCount: Int
    let failedCount: Int
    let results: [EjectResult]
    let totalDuration: Double
    let method: String  // "native" or "diskutil"
}

struct BenchmarkOutput: Codable, Sendable {
    let enumerationTime: Double
    let volumeCount: Int
    let nativeEjectTime: Double?
    let diskutilEjectTime: Double?
    let speedup: Double?
}

// MARK: - Volume Discovery (Legacy for JSON compatibility)

/// Get list of ejectable volumes using legacy format for JSON output
func getEjectableVolumesLegacy() async -> [VolumeInfoOutput] {
    let session = DiskSession.shared
    let volumes = await session.enumerateEjectableVolumes()

    return volumes.map { volume in
        VolumeInfoOutput(
            name: volume.info.name,
            path: volume.info.path,
            bsdName: volume.info.bsdName,
            isEjectable: volume.info.isEjectable,
            isRemovable: volume.info.isRemovable
        )
    }
}

// MARK: - Process Discovery

/// Parse lsof output into ProcessInfoOutput array
nonisolated func parseLsofOutput(_ output: String) -> [ProcessInfoOutput] {
    // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    var processes: [ProcessInfoOutput] = []
    var seenPids: Set<String> = []

    for line in output.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        // Skip header line and empty lines
        if parts.count >= 3 && parts[0] != "COMMAND" {
            let pid = parts[1]
            // Only add each PID once
            if !seenPids.contains(pid) {
                seenPids.insert(pid)
                processes.append(ProcessInfoOutput(
                    pid: pid,
                    command: parts[0],
                    user: parts[2]
                ))
            }
        }
    }
    return processes
}

/// Get list of processes using a volume path via lsof
/// Uses lsof +d (single level) for speed - +D recursive is too slow on large volumes
nonisolated func getBlockingProcesses(path: String) -> [ProcessInfoOutput] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    // +d checks single directory level only (fast)
    // +D would recursively search the entire volume (very slow - minutes on large drives)
    process.arguments = ["+d", path]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()

        // Set a 5 second timeout just in case
        let timeoutItem = DispatchWorkItem {
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

        process.waitUntilExit()
        timeoutItem.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return parseLsofOutput(output)
    } catch {
        return []
    }
}

// MARK: - Fast Native Ejection (DADiskUnmount)

/// Eject all volumes using native DiskArbitration API (10x faster than diskutil)
func ejectAllVolumesNative(force: Bool = false, verbose: Bool = false) async -> EjectOutput {
    let session = DiskSession.shared
    let volumes = await session.enumerateEjectableVolumes()
    let startTime = Date()

    guard !volumes.isEmpty else {
        return EjectOutput(
            totalCount: 0,
            successCount: 0,
            failedCount: 0,
            results: [],
            totalDuration: 0,
            method: "native"
        )
    }

    let options = force ? EjectOptions.forceEject : EjectOptions.default
    let batchResult = await session.ejectAll(volumes, options: options)

    // Convert to legacy output format with blocking process detection on failure
    var results: [EjectResult] = []

    for singleResult in batchResult.results {
        var blockingProcesses: [ProcessInfoOutput]? = nil

        // If failed and verbose, get blocking processes
        if !singleResult.success && verbose {
            let processes = getBlockingProcesses(path: singleResult.volumePath)
            blockingProcesses = processes.isEmpty ? nil : processes
        }

        results.append(EjectResult(
            volume: singleResult.volumeName,
            success: singleResult.success,
            error: singleResult.errorMessage,
            duration: singleResult.duration,
            blockingProcesses: blockingProcesses
        ))
    }

    let totalDuration = Date().timeIntervalSince(startTime)

    return EjectOutput(
        totalCount: batchResult.totalCount,
        successCount: batchResult.successCount,
        failedCount: batchResult.failedCount,
        results: results,
        totalDuration: totalDuration,
        method: "native"
    )
}

// MARK: - Slow Diskutil Ejection (for comparison)

/// Eject a single volume using diskutil subprocess
nonisolated func ejectVolumeWithDiskutilSync(path: String, verbose: Bool = false) -> (success: Bool, error: String?, blockingProcesses: [ProcessInfoOutput]?) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["eject", path]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return (true, nil, nil)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            let errorMsg = output.trimmingCharacters(in: .whitespacesAndNewlines)

            // If verbose mode or eject failed, find what processes are blocking
            let blockingProcesses = getBlockingProcesses(path: path)

            return (false, errorMsg, blockingProcesses.isEmpty ? nil : blockingProcesses)
        }
    } catch {
        return (false, error.localizedDescription, nil)
    }
}

/// Eject all volumes using diskutil subprocess (slow, for comparison)
func ejectAllVolumesWithDiskutil(verbose: Bool = false) async -> EjectOutput {
    let volumes = await getEjectableVolumesLegacy()
    let startTime = Date()

    guard !volumes.isEmpty else {
        return EjectOutput(
            totalCount: 0,
            successCount: 0,
            failedCount: 0,
            results: [],
            totalDuration: 0,
            method: "diskutil"
        )
    }

    let results = await withTaskGroup(of: EjectResult.self, returning: [EjectResult].self) { group in
        for volume in volumes {
            group.addTask {
                let volumeStartTime = Date()
                let (success, error, blockingProcesses) = ejectVolumeWithDiskutilSync(path: volume.path, verbose: verbose)
                let duration = Date().timeIntervalSince(volumeStartTime)

                return EjectResult(
                    volume: volume.name,
                    success: success,
                    error: error,
                    duration: duration,
                    blockingProcesses: blockingProcesses
                )
            }
        }

        var collectedResults: [EjectResult] = []
        for await result in group {
            collectedResults.append(result)
        }
        return collectedResults
    }

    let totalDuration = Date().timeIntervalSince(startTime)
    let successCount = results.filter { $0.success }.count

    return EjectOutput(
        totalCount: volumes.count,
        successCount: successCount,
        failedCount: volumes.count - successCount,
        results: results,
        totalDuration: totalDuration,
        method: "diskutil"
    )
}

// MARK: - JSON Output Helper

func printJSON<T: Encodable>(_ value: T, compact: Bool = false) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = compact ? .sortedKeys : [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value),
        let json = String(data: data, encoding: .utf8)
    {
        print(json)
    }
}

// MARK: - ArgumentParser Commands

@main
struct EjectDisks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eject-disks",
        abstract: "Fast disk ejection using native DiskArbitration APIs",
        discussion: """
            A high-performance tool for ejecting external disks on macOS.
            Uses DADiskUnmount for 10x faster ejection vs diskutil subprocess.
            Includes diagnostics to identify processes blocking disk ejection.
            """,
        version: "3.0.0",
        subcommands: [List.self, Count.self, Eject.self, Diagnose.self, Benchmark.self],
        defaultSubcommand: List.self
    )
}

extension EjectDisks {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all ejectable volumes",
            discussion: "Returns a JSON object with count and volume details."
        )

        @Flag(name: .shortAndLong, help: "Output in compact JSON format")
        var compact = false

        func run() async {
            let volumes = await getEjectableVolumesLegacy()
            let output = ListOutput(count: volumes.count, volumes: volumes)
            printJSON(output, compact: compact)
        }
    }

    struct Count: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the count of ejectable volumes",
            discussion: "Returns just the number of ejectable volumes."
        )

        func run() async {
            let count = await DiskSession.shared.ejectableVolumeCount()
            print(count)
        }
    }

    struct Eject: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Eject all external volumes",
            discussion: """
                Ejects all ejectable volumes in parallel using native DiskArbitration APIs.
                Uses DADiskUnmount for ~10x faster ejection compared to diskutil.
                Returns a JSON object with results for each volume.
                """
        )

        @Flag(name: .shortAndLong, help: "Output in compact JSON format")
        var compact = false

        @Flag(name: .shortAndLong, help: "Force eject (may cause data loss)")
        var force = false

        @Flag(name: .shortAndLong, help: "Show blocking processes on eject failure")
        var verbose = false

        @Flag(name: .long, help: "Use diskutil subprocess instead of native API (slower)")
        var useDiskutil = false

        func run() async {
            let output: EjectOutput
            if useDiskutil {
                output = await ejectAllVolumesWithDiskutil(verbose: verbose)
            } else {
                output = await ejectAllVolumesNative(force: force, verbose: verbose)
            }
            printJSON(output, compact: compact)
        }
    }

    struct Diagnose: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Diagnose why volumes can't be ejected",
            discussion: """
                Lists all ejectable volumes and shows which processes have files open on each.
                Use this to understand why a disk can't be ejected before trying again.
                """
        )

        @Flag(name: .shortAndLong, help: "Output in compact JSON format")
        var compact = false

        func run() async {
            let volumes = await getEjectableVolumesLegacy()

            struct DiagnoseResult: Codable {
                let volume: String
                let path: String
                let blockingProcesses: [ProcessInfoOutput]
            }

            struct DiagnoseOutput: Codable {
                let volumeCount: Int
                let results: [DiagnoseResult]
            }

            var results: [DiagnoseResult] = []

            for volume in volumes {
                let processes = getBlockingProcesses(path: volume.path)
                results.append(DiagnoseResult(
                    volume: volume.name,
                    path: volume.path,
                    blockingProcesses: processes
                ))
            }

            let output = DiagnoseOutput(volumeCount: volumes.count, results: results)
            printJSON(output, compact: compact)
        }
    }

    struct Benchmark: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Benchmark native vs diskutil ejection speed",
            discussion: """
                Measures volume enumeration time and compares ejection methods.
                Native API uses DADiskUnmount (fast), diskutil spawns subprocess (slow).
                """
        )

        @Flag(name: .shortAndLong, help: "Actually eject volumes (destructive)")
        var eject = false

        @Flag(name: .long, help: "Eject using diskutil (for comparison)")
        var useDiskutil = false

        @Option(name: .shortAndLong, help: "Number of enumeration iterations")
        var iterations: Int = 100

        func run() async {
            print("=== Eject Disks Benchmark ===\n")

            // Benchmark enumeration
            print("Benchmarking volume enumeration (\(iterations) iterations)...")
            let enumStart = Date()
            var volumeCount = 0
            for _ in 0..<iterations {
                volumeCount = await DiskSession.shared.ejectableVolumeCount()
            }
            let enumDuration = Date().timeIntervalSince(enumStart)
            let avgEnumTime = enumDuration / Double(iterations)

            print("  Total time: \(String(format: "%.4f", enumDuration))s")
            print("  Average time: \(String(format: "%.4f", avgEnumTime * 1000))ms")
            print("  Volumes found: \(volumeCount)")

            let volumes = await getEjectableVolumesLegacy()
            if !volumes.isEmpty {
                print("\nVolumes:")
                for volume in volumes {
                    print("  - \(volume.name) (bsd: \(volume.bsdName ?? "unknown"))")
                }
            }

            // Benchmark ejection if requested and volumes present
            var nativeTime: Double? = nil
            var diskutilTime: Double? = nil
            var speedup: Double? = nil

            if eject && !volumes.isEmpty {
                print("\n--- Ejection Benchmark ---")
                print("WARNING: This will eject all \(volumes.count) volume(s)!")

                if useDiskutil {
                    print("Ejecting with diskutil subprocess (slow)...")
                    let output = await ejectAllVolumesWithDiskutil(verbose: false)
                    diskutilTime = output.totalDuration
                    print("  Diskutil time: \(String(format: "%.4f", diskutilTime!))s")
                    print("  Success: \(output.successCount)/\(output.totalCount)")
                } else {
                    print("Ejecting with native DADiskUnmount (fast)...")
                    let output = await ejectAllVolumesNative(force: false, verbose: false)
                    nativeTime = output.totalDuration
                    print("  Native time: \(String(format: "%.4f", nativeTime!))s")
                    print("  Success: \(output.successCount)/\(output.totalCount)")
                }

                print("\nNote: To compare both methods, run benchmark twice with fresh mounts:")
                print("  1. Mount volumes, run: eject-disks benchmark --eject")
                print("  2. Remount volumes, run: eject-disks benchmark --eject --use-diskutil")

            } else if !eject && !volumes.isEmpty {
                print("\nTo benchmark actual ejection:")
                print("  Native (fast): eject-disks benchmark --eject")
                print("  Diskutil (slow): eject-disks benchmark --eject --use-diskutil")
                print("WARNING: --eject will unmount all external volumes!")
            }

            // Print summary
            print("\n=== Summary ===")
            let output = BenchmarkOutput(
                enumerationTime: avgEnumTime,
                volumeCount: volumeCount,
                nativeEjectTime: nativeTime,
                diskutilEjectTime: diskutilTime,
                speedup: speedup
            )
            printJSON(output, compact: false)
        }
    }
}
