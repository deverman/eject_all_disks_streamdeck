//
//  EjectDisks.swift
//  Fast disk ejection using native macOS APIs
//
//  Uses DiskArbitration framework for high-performance parallel ejection
//

import ArgumentParser
import AppKit
import DiskArbitration
import Foundation

// MARK: - JSON Output Types

struct VolumeInfo: Codable {
    let name: String
    let path: String
    let bsdName: String?
}

struct EjectResult: Codable {
    let volume: String
    let success: Bool
    let error: String?
    let duration: Double
}

struct ListOutput: Codable {
    let count: Int
    let volumes: [VolumeInfo]
}

struct EjectOutput: Codable {
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
    let excludePatterns: [String] = [
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
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsLocalKey]),
           let isEjectable = resourceValues.volumeIsEjectable,
           let isRemovable = resourceValues.volumeIsRemovable {
            // Include if ejectable OR removable (external drives)
            if !isEjectable && !isRemovable {
                continue
            }
        }

        // Get BSD name if available
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

// MARK: - Disk Ejection

/// Eject using NSWorkspace (simpler, reliable)
func ejectVolumeNS(path: String) -> (Bool, String?) {
    let url = URL(fileURLWithPath: path)
    var error: NSError?

    let success = NSWorkspace.shared.unmountAndEjectDevice(at: url, error: &error)

    if success {
        return (true, nil)
    } else {
        return (false, error?.localizedDescription ?? "Unknown error")
    }
}

/// Eject all volumes in parallel using dispatch queues
func ejectAllVolumesParallel(volumes: [VolumeInfo]) -> EjectOutput {
    let startTime = Date()
    var results: [EjectResult] = []
    let resultsLock = NSLock()
    let group = DispatchGroup()

    // Create a DA session for this operation
    guard let session = DASessionCreate(kCFAllocatorDefault) else {
        // Fallback to NSWorkspace if DA session fails
        return ejectAllVolumesNSWorkspace(volumes: volumes)
    }

    // Set up the session's run loop
    let queue = DispatchQueue(label: "com.deverman.ejectdisks", attributes: .concurrent)
    DASessionSetDispatchQueue(session, queue)

    for volume in volumes {
        group.enter()
        let volumeStartTime = Date()

        queue.async {
            let semaphore = DispatchSemaphore(value: 0)
            var ejected = false
            var errorMsg: String? = nil

            // Try DiskArbitration first (fastest)
            let url = URL(fileURLWithPath: volume.path)
            if let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) {
                let unmountOptions = DADiskUnmountOptions(kDADiskUnmountOptionWhole)

                DADiskUnmount(disk, unmountOptions, { disk, dissenter, context in
                    let semPtr = context!.assumingMemoryBound(to: DispatchSemaphore.self)

                    if dissenter != nil {
                        // Try eject even if unmount reports an issue
                        DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, dissenter, _ in
                            semPtr.pointee.signal()
                        }, context)
                    } else {
                        DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, _, _ in
                            semPtr.pointee.signal()
                        }, context)
                    }
                }, UnsafeMutableRawPointer(&semaphore))

                // Wait with timeout
                let waitResult = semaphore.wait(timeout: .now() + 5.0)

                if waitResult == .timedOut {
                    errorMsg = "Operation timed out"
                    ejected = false
                } else {
                    // Check if volume is still there
                    ejected = !FileManager.default.fileExists(atPath: volume.path)
                    if !ejected {
                        // Give it a moment and check again
                        Thread.sleep(forTimeInterval: 0.1)
                        ejected = !FileManager.default.fileExists(atPath: volume.path)
                    }
                    if !ejected {
                        errorMsg = "Volume still present after eject"
                    }
                }
            } else {
                // Fallback to NSWorkspace
                let (success, error) = ejectVolumeNS(path: volume.path)
                ejected = success
                errorMsg = error
            }

            let duration = Date().timeIntervalSince(volumeStartTime)

            resultsLock.lock()
            results.append(EjectResult(
                volume: volume.name,
                success: ejected,
                error: errorMsg,
                duration: duration
            ))
            resultsLock.unlock()

            group.leave()
        }
    }

    // Wait for all ejections to complete
    group.wait()

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

/// Fallback: Eject using NSWorkspace in parallel
func ejectAllVolumesNSWorkspace(volumes: [VolumeInfo]) -> EjectOutput {
    let startTime = Date()
    var results: [EjectResult] = []
    let resultsLock = NSLock()
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "com.deverman.ejectdisks.ns", attributes: .concurrent)

    for volume in volumes {
        group.enter()
        let volumeStartTime = Date()

        queue.async {
            let (success, error) = ejectVolumeNS(path: volume.path)
            let duration = Date().timeIntervalSince(volumeStartTime)

            resultsLock.lock()
            results.append(EjectResult(
                volume: volume.name,
                success: success,
                error: error,
                duration: duration
            ))
            resultsLock.unlock()

            group.leave()
        }
    }

    group.wait()

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

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
            Uses the DiskArbitration framework for parallel ejection operations.
            """,
        version: "1.0.0",
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

            let encoder = JSONEncoder()
            encoder.outputFormatting = compact ? .sortedKeys : [.prettyPrinted, .sortedKeys]

            if let data = try? encoder.encode(output),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
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

    struct Eject: ParsableCommand {
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

        func run() {
            let volumes = getEjectableVolumes()

            let output: EjectOutput
            if volumes.isEmpty {
                output = EjectOutput(
                    totalCount: 0,
                    successCount: 0,
                    failedCount: 0,
                    results: [],
                    totalDuration: 0
                )
            } else {
                output = ejectAllVolumesParallel(volumes: volumes)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = compact ? .sortedKeys : [.prettyPrinted, .sortedKeys]

            if let data = try? encoder.encode(output),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        }
    }
}
