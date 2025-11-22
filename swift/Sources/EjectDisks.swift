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
        "Update"
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

        // Verify it's a mount point and is ejectable
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            continue
        }

        // Check if volume is ejectable using URL resource values
        let url = URL(fileURLWithPath: path)
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey]),
           let isEjectable = resourceValues.volumeIsEjectable,
           let isRemovable = resourceValues.volumeIsRemovable {
            // Include if ejectable OR removable (external drives)
            if !isEjectable && !isRemovable {
                continue
            }
        }

        // Get BSD name if available (for informational purposes)
        var bsdName: String? = nil
        if let session = DASessionCreate(kCFAllocatorDefault),
           let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
           let bsdNameCStr = DADiskGetBSDName(disk) {
            bsdName = String(cString: bsdNameCStr)
        }

        volumes.append(VolumeInfo(name: name, path: path, bsdName: bsdName))
    }

    return volumes
}

// MARK: - Disk Ejection (Swift 6 Concurrency)

/// Eject a single volume using NSWorkspace
/// This is the most reliable method and works well with Swift concurrency
func ejectVolume(path: String) async -> (success: Bool, error: String?) {
    // NSWorkspace operations need to run on main actor for safety
    await MainActor.run {
        let url = URL(fileURLWithPath: path)
        var error: NSError?
        let success = NSWorkspace.shared.unmountAndEjectDevice(at: url, error: &error)
        return (success, error?.localizedDescription)
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

    // Use TaskGroup for parallel ejection
    let results = await withTaskGroup(of: EjectResult.self, returning: [EjectResult].self) { group in
        for volume in volumes {
            group.addTask {
                let volumeStartTime = Date()
                let (success, error) = await ejectVolume(path: volume.path)
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

// MARK: - JSON Output Helper

func printJSON<T: Encodable>(_ value: T, compact: Bool = false) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = compact ? .sortedKeys : [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value),
       let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

// MARK: - ArgumentParser Commands

@main
struct EjectDisks: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eject-disks",
        abstract: "Fast disk ejection using native macOS APIs",
        discussion: """
            A high-performance tool for ejecting external disks on macOS.
            Uses NSWorkspace with Swift concurrency for parallel ejection operations.
            """,
        version: "2.0.0",
        subcommands: [List.self, Count.self, Eject.self],
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

        func run() async {
            let volumes = getEjectableVolumes()
            let output = await ejectAllVolumes(volumes: volumes, force: force)
            printJSON(output, compact: compact)
        }
    }
}
