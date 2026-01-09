//
//  IntegrationTests.swift
//  EjectAllDisksPluginTests
//
//  Integration tests for the plugin with SwiftDiskArbitration
//

import Testing
import Foundation
import SwiftDiskArbitration
@testable import EjectAllDisksPlugin

@Suite("DiskArbitration Integration Tests")
struct DiskArbitrationIntegrationTests {

    // MARK: - Session Creation

    @Test("Can create DiskSession")
    func createSession() throws {
        let session = try DiskSession()
        #expect(session != nil)
    }

    @Test("Shared session is available")
    func sharedSession() {
        let session = DiskSession.shared
        #expect(session != nil)
    }

    @Test("Multiple sessions can coexist")
    func multipleSessions() throws {
        let session1 = try DiskSession()
        let session2 = try DiskSession()

        let count1 = await session1.ejectableVolumeCount()
        let count2 = await session2.ejectableVolumeCount()

        #expect(count1 == count2, "Both sessions should see the same volume count")
    }

    // MARK: - Volume Enumeration

    @Test("Can get ejectable volume count")
    func getVolumeCount() async {
        let session = DiskSession.shared
        let count = await session.ejectableVolumeCount()

        // Count should be non-negative
        #expect(count >= 0)
    }

    @Test("Can enumerate ejectable volumes")
    func enumerateVolumes() async {
        let session = DiskSession.shared
        let volumes = await session.enumerateEjectableVolumes()

        // Should return an array (possibly empty)
        #expect(volumes.count >= 0)

        // Each volume should have valid info
        for volume in volumes {
            #expect(!volume.info.name.isEmpty, "Volume name should not be empty")
            #expect(volume.info.path.hasPrefix("/Volumes/"), "Volume path should start with /Volumes/")
        }
    }

    @Test("Volume count matches enumeration count")
    func volumeCountMatchesEnumeration() async {
        let session = DiskSession.shared

        let count = await session.ejectableVolumeCount()
        let volumes = await session.enumerateEjectableVolumes()

        #expect(count == volumes.count, "Count should match enumerated volumes")
    }

    // MARK: - Eject Options

    @Test("Default eject options are correct")
    func defaultEjectOptions() {
        let options = EjectOptions.default

        #expect(!options.force, "Default should not force eject")
        #expect(options.ejectPhysicalDevice, "Default should eject physical device")
    }

    @Test("Unmount-only options are correct")
    func unmountOnlyOptions() {
        let options = EjectOptions.unmountOnly

        #expect(!options.force, "Unmount-only should not force")
        #expect(!options.ejectPhysicalDevice, "Unmount-only should not eject physical device")
    }

    @Test("Force eject options are correct")
    func forceEjectOptions() {
        let options = EjectOptions.forceEject

        #expect(options.force, "Force eject should have force=true")
        #expect(options.ejectPhysicalDevice, "Force eject should eject physical device")
    }

    // MARK: - Empty Batch Handling

    @Test("Empty volume batch returns zero counts")
    func emptyBatchResult() async throws {
        let session = try DiskSession()
        let result = await session.ejectAll([], options: .default)

        #expect(result.totalCount == 0)
        #expect(result.successCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.results.isEmpty)
        #expect(result.totalDuration == 0)
    }

    // MARK: - Batch Result Types

    @Test("BatchEjectResult has correct structure")
    func batchResultStructure() async throws {
        let session = try DiskSession()
        let result = await session.ejectAll([], options: .default)

        // Verify all properties are accessible
        _ = result.totalCount
        _ = result.successCount
        _ = result.failedCount
        _ = result.results
        _ = result.totalDuration

        #expect(result.totalCount == result.successCount + result.failedCount)
    }

    @Test("SingleEjectResult is Codable")
    func singleResultCodable() throws {
        let result = SingleEjectResult(
            volumeName: "Test Drive",
            volumePath: "/Volumes/Test Drive",
            success: true,
            errorMessage: nil,
            duration: 0.05
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SingleEjectResult.self, from: data)

        #expect(decoded.volumeName == result.volumeName)
        #expect(decoded.volumePath == result.volumePath)
        #expect(decoded.success == result.success)
        #expect(decoded.errorMessage == result.errorMessage)
        #expect(decoded.duration == result.duration)
    }

    @Test("Failed SingleEjectResult includes error message")
    func failedResultMessage() throws {
        let result = SingleEjectResult(
            volumeName: "Busy Drive",
            volumePath: "/Volumes/Busy Drive",
            success: false,
            errorMessage: "Resource busy",
            duration: 0.01
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("Resource busy"))
        #expect(json.contains("\"success\":false") || json.contains("\"success\": false"))
    }
}

@Suite("Plugin Component Integration Tests")
struct PluginComponentIntegrationTests {

    // MARK: - Icon Generation with Real Data

    @Test("Icon updates with real disk count")
    func iconWithRealDiskCount() async {
        let session = DiskSession.shared
        let count = await session.ejectableVolumeCount()

        let svg = IconGenerator.createNormalSvgRaw(count: count)

        #expect(svg.contains("<svg"))
        if count > 0 {
            #expect(svg.contains(">\(count)</text>"))
        }
    }

    // MARK: - Performance Tests

    @Test("Volume count is fast", .timeLimit(.seconds(1)))
    func volumeCountPerformance() async {
        let session = DiskSession.shared

        // Should complete well within 1 second
        for _ in 0..<10 {
            _ = await session.ejectableVolumeCount()
        }
    }

    @Test("Icon generation is fast", .timeLimit(.seconds(1)))
    func iconGenerationPerformance() {
        // Generate many icons quickly
        for i in 0..<100 {
            _ = IconGenerator.createNormalSvg(count: i % 10)
        }
    }

    @Test("Full enumeration is reasonably fast", .timeLimit(.seconds(5)))
    func enumerationPerformance() async {
        let session = DiskSession.shared

        for _ in 0..<5 {
            _ = await session.enumerateEjectableVolumes()
        }
    }
}

@Suite("Real Hardware Tests", .disabled("Requires external volumes"))
struct RealHardwareTests {
    // These tests require actual external volumes and are disabled by default
    // Enable and run manually when testing with real hardware

    @Test("Can eject real external volume")
    func ejectRealVolume() async throws {
        let session = try DiskSession()
        let volumes = await session.enumerateEjectableVolumes()

        guard let volume = volumes.first else {
            Issue.record("No external volumes available for testing")
            return
        }

        print("Testing eject of: \(volume.info.name)")
        let result = await session.unmount(volume)

        print("Result: success=\(result.success), duration=\(result.duration)s")
        if let error = result.error {
            print("Error: \(error)")
        }

        // We can't guarantee success (volume might be in use)
        // but the operation should complete
        #expect(result.duration >= 0)
    }

    @Test("Can eject all real volumes")
    func ejectAllRealVolumes() async throws {
        let session = try DiskSession()
        let volumes = await session.enumerateEjectableVolumes()

        guard !volumes.isEmpty else {
            Issue.record("No external volumes available for testing")
            return
        }

        print("Testing batch eject of \(volumes.count) volume(s)")
        let result = await session.ejectAll(volumes)

        print("Batch result: \(result.successCount)/\(result.totalCount) succeeded")
        print("Duration: \(result.totalDuration)s")

        for singleResult in result.results {
            let status = singleResult.success ? "OK" : "FAIL"
            print("  [\(status)] \(singleResult.volumeName)")
            if let error = singleResult.errorMessage {
                print("       Error: \(error)")
            }
        }

        // Verify counts are consistent
        #expect(result.totalCount == volumes.count)
        #expect(result.successCount + result.failedCount == result.totalCount)
    }
}
