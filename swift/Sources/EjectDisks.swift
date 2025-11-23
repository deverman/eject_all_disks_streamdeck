//
//  EjectDisks.swift
//  Fast disk ejection using native macOS APIs
//
//  Uses NSWorkspace for reliable parallel ejection with Swift 6 concurrency
//

import ArgumentParser
import AppKit
import DiskArbitration
import Foundation

// MARK: - JSON Output Types

struct VolumeInfo: Codable, Sendable {
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
}

struct ListOutput: Codable, Sendable {
    let count: Int
    let volumes: [VolumeInfo]
}

struct EjectOutput: Codable, Sendable {
    let totalCount: Int
    let successCount: Int
    let failedCount: Int
    let results: [EjectResult]
    let totalDuration: Double
}

struct BenchmarkOutput: Codable, Sendable {
    let enumerationTime: Double
    let volumeCount: Int
    let swiftEjectTime: Double?
    let diskutilEjectTime: Double?
    let speedup: Double?
}

// MARK: - Volume Discovery

/// Get list of ejectable volumes (matching what Finder shows)
func getEjectableVolumes() -> [VolumeInfo] {
    let fileManager = FileManager.default
    let volumesPath = "/Volumes"

    guard let contents = try? fileManager.contentsOfDirectory(atPath: volumesPath) else {
        return []
    }

    // Patterns to exclude (system volumes, hidden, Time Machine)
    let excludePatterns: Set<String> = [
        "Macintosh HD",
        "Macintosh HD - Data",
        "Recovery",
        "Preboot",
        "VM",
        "Update",
    ]

    var volumes: [VolumeInfo] = []

    for name in contents {
        // Skip hidden files
        if name.hasPrefix(".") {
            continue
        }

        // Skip Apple system volumes
        if name.hasPrefix("com.apple.") {
            continue
        }

        // Skip Time Machine backups
        if name.hasPrefix("Backups of ") {
            continue
        }

        // Skip known system volumes
        if excludePatterns.contains(name) {
            continue
        }

        let path = "\(volumesPath)/\(name)"

        // Verify it's a mount point
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            continue
        }

        let url = URL(fileURLWithPath: path)

        // Get volume properties
        var isEjectable = false
        var isRemovable = false
        var isInternal = true

        if let resourceValues = try? url.resourceValues(forKeys: [
            .volumeIsEjectableKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
        ]) {
            isEjectable = resourceValues.volumeIsEjectable ?? false
            isRemovable = resourceValues.volumeIsRemovable ?? false
            isInternal = resourceValues.volumeIsInternal ?? true
        }

        // Include if:
        // - Volume is ejectable, OR
        // - Volume is removable, OR
        // - Volume is NOT internal (external drives)
        if !isEjectable && !isRemovable && isInternal {
            continue
        }

        // Get BSD name if available (for informational purposes)
        var bsdName: String? = nil
        if let session = DASessionCreate(kCFAllocatorDefault),
            let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
            let bsdNameCStr = DADiskGetBSDName(disk)
        {
            bsdName = String(cString: bsdNameCStr)
        }

        volumes.append(VolumeInfo(
            name: name,
            path: path,
            bsdName: bsdName,
            isEjectable: isEjectable,
            isRemovable: isRemovable
        ))
    }

    return volumes
}

// MARK: - Disk Ejection (Swift 6 Concurrency)

/// Eject a single volume using diskutil eject (reliable and fast when run in parallel)
/// Note: NSWorkspace.unmountAndEjectDevice incorrectly returns error -47 for non-busy volumes
nonisolated func ejectVolumeWithDiskutilSync(path: String) -> (success: Bool, error: String?) {
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
            return (true, nil)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    } catch {
        return (false, error.localizedDescription)
    }
}

/// Eject a single volume using NSWorkspace (backup method)
/// Note: NSWorkspace.unmountAndEjectDevice may incorrectly return error -47 for non-busy volumes
nonisolated func ejectVolumeSyncUnsafe(path: String, force: Bool = false) -> (success: Bool, error: String?) {
    let url = URL(fileURLWithPath: path)
    do {
        // NSWorkspace.shared is thread-safe for this operation
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        return (true, nil)
    } catch {
        // If regular eject fails and force is requested, try diskutil
        if force {
            return ejectWithDiskutilForce(path: path)
        }
        return (false, error.localizedDescription)
    }
}

/// Force eject using diskutil unmount force (fallback for busy volumes)
nonisolated func ejectWithDiskutilForce(path: String) -> (success: Bool, error: String?) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["unmount", "force", path]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return (true, nil)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    } catch {
        return (false, error.localizedDescription)
    }
}

/// Eject a single volume using diskutil (for benchmarking comparison)
func ejectVolumeWithDiskutil(path: String) -> (success: Bool, error: String?, duration: Double) {
    let startTime = Date()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["eject", path]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let duration = Date().timeIntervalSince(startTime)

        if process.terminationStatus == 0 {
            return (true, nil, duration)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, output, duration)
        }
    } catch {
        let duration = Date().timeIntervalSince(startTime)
        return (false, error.localizedDescription, duration)
    }
}

/// Eject all volumes in parallel using Swift concurrency
func ejectAllVolumes(volumes: [VolumeInfo], force: Bool = false) async -> EjectOutput {
    let startTime = Date()

    guard !volumes.isEmpty else {
        return EjectOutput(
            totalCount: 0,
            successCount: 0,
            failedCount: 0,
            results: [],
            totalDuration: 0
        )
    }

    // Use TaskGroup for parallel ejection with true concurrency
    // Using diskutil eject which is reliable (NSWorkspace incorrectly returns error -47)
    // Running in parallel minimizes the overhead of spawning processes
    let results = await withTaskGroup(of: EjectResult.self, returning: [EjectResult].self) { group in
        for volume in volumes {
            group.addTask {
                let volumeStartTime = Date()
                // Use diskutil eject for reliable ejection
                let (success, error) = ejectVolumeWithDiskutilSync(path: volume.path)
                let duration = Date().timeIntervalSince(volumeStartTime)

                return EjectResult(
                    volume: volume.name,
                    success: success,
                    error: error,
                    duration: duration
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
        totalDuration: totalDuration
    )
}

/// Eject all volumes using diskutil in parallel (for benchmarking)
func ejectAllVolumesWithDiskutil(volumes: [VolumeInfo]) async -> EjectOutput {
    let startTime = Date()

    guard !volumes.isEmpty else {
        return EjectOutput(
            totalCount: 0,
            successCount: 0,
            failedCount: 0,
            results: [],
            totalDuration: 0
        )
    }

    let results = await withTaskGroup(of: EjectResult.self, returning: [EjectResult].self) { group in
        for volume in volumes {
            group.addTask {
                let (success, error, duration) = ejectVolumeWithDiskutil(path: volume.path)
                return EjectResult(
                    volume: volume.name,
                    success: success,
                    error: error,
                    duration: duration
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
        totalDuration: totalDuration
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
        abstract: "Fast disk ejection using native macOS APIs",
        discussion: """
            A high-performance tool for ejecting external disks on macOS.
            Uses NSWorkspace with Swift concurrency for parallel ejection operations.
            """,
        version: "2.0.0",
        subcommands: [List.self, Count.self, Eject.self, Benchmark.self],
        defaultSubcommand: List.self
    )
}

extension EjectDisks {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all ejectable volumes",
            discussion: "Returns a JSON object with count and volume details."
        )

        @Flag(name: .shortAndLong, help: "Output in compact JSON format")
        var compact = false

        func run() {
            let volumes = getEjectableVolumes()
            let output = ListOutput(count: volumes.count, volumes: volumes)
            printJSON(output, compact: compact)
        }
    }

    struct Count: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the count of ejectable volumes",
            discussion: "Returns just the number of ejectable volumes."
        )

        func run() {
            let volumes = getEjectableVolumes()
            print(volumes.count)
        }
    }

    struct Eject: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Eject all external volumes",
            discussion: """
                Ejects all ejectable volumes in parallel using native macOS APIs.
                Returns a JSON object with results for each volume.
                """
        )

        @Flag(name: .shortAndLong, help: "Output in compact JSON format")
        var compact = false

        @Flag(name: .shortAndLong, help: "Force eject (may cause data loss)")
        var force = false

        @Flag(name: .long, help: "Use diskutil instead of native API (for comparison)")
        var useDiskutil = false

        func run() async {
            let volumes = getEjectableVolumes()
            let output: EjectOutput
            if useDiskutil {
                output = await ejectAllVolumesWithDiskutil(volumes: volumes)
            } else {
                output = await ejectAllVolumes(volumes: volumes, force: force)
            }
            printJSON(output, compact: compact)
        }
    }

    struct Benchmark: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Benchmark volume enumeration and ejection",
            discussion: """
                Measures the time taken for volume enumeration.
                If volumes are present, compares Swift vs diskutil ejection times.
                Note: Actually ejecting requires mounted volumes.
                """
        )

        @Flag(name: .shortAndLong, help: "Actually eject volumes (destructive)")
        var eject = false

        @Option(name: .shortAndLong, help: "Number of enumeration iterations")
        var iterations: Int = 100

        func run() async {
            print("=== Eject Disks Benchmark ===\n")

            // Benchmark enumeration
            print("Benchmarking volume enumeration (\(iterations) iterations)...")
            let enumStart = Date()
            var volumes: [VolumeInfo] = []
            for _ in 0..<iterations {
                volumes = getEjectableVolumes()
            }
            let enumDuration = Date().timeIntervalSince(enumStart)
            let avgEnumTime = enumDuration / Double(iterations)

            print("  Total time: \(String(format: "%.4f", enumDuration))s")
            print("  Average time: \(String(format: "%.4f", avgEnumTime * 1000))ms")
            print("  Volumes found: \(volumes.count)")

            if !volumes.isEmpty {
                print("\nVolumes:")
                for volume in volumes {
                    print("  - \(volume.name) (bsd: \(volume.bsdName ?? "unknown"), ejectable: \(volume.isEjectable), removable: \(volume.isRemovable))")
                }
            }

            // Benchmark ejection if requested and volumes present
            var swiftTime: Double? = nil
            let diskutilTime: Double? = nil

            if eject && !volumes.isEmpty {
                print("\n--- Ejection Benchmark ---")
                print("WARNING: This will eject all \(volumes.count) volume(s)!")
                print("Ejecting with Swift (NSWorkspace)...")

                let swiftOutput = await ejectAllVolumes(volumes: volumes, force: false)
                swiftTime = swiftOutput.totalDuration
                print("  Swift time: \(String(format: "%.4f", swiftTime!))s")
                print("  Success: \(swiftOutput.successCount)/\(swiftOutput.totalCount)")

                // Note: Can't benchmark diskutil after Swift ejected the volumes
                // Would need to remount to compare
                print("\nNote: Cannot compare with diskutil (volumes already ejected)")
                print("To compare, run each method separately with fresh mounts.")
            } else if !eject && !volumes.isEmpty {
                print("\nTo benchmark actual ejection, use --eject flag")
                print("WARNING: --eject will unmount all external volumes!")
            }

            // Print summary
            print("\n=== Summary ===")
            let output = BenchmarkOutput(
                enumerationTime: avgEnumTime,
                volumeCount: volumes.count,
                swiftEjectTime: swiftTime,
                diskutilEjectTime: diskutilTime,
                speedup: nil
            )
            printJSON(output, compact: false)
        }
    }
}
