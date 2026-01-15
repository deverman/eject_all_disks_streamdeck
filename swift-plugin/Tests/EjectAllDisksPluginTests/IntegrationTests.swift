//
//  IntegrationTests.swift
//  EjectAllDisksPluginTests
//
//  Integration tests for the plugin with SwiftDiskArbitration
//

import Testing
import Foundation
import SwiftDiskArbitration

@Suite("DiskArbitration Integration Tests")
struct DiskArbitrationIntegrationTests {

    // MARK: - Session Creation

    @Test("Can create DiskSession")
    func createSession() throws {
        let session = try DiskSession()
        // Session was created successfully if we reach here
        _ = session
    }

    @Test("Shared session is available")
    func sharedSession() {
        let session = DiskSession.shared
        // Shared session is available if we can access it
        _ = session
    }

    @Test("Multiple sessions can coexist")
    func multipleSessions() async throws {
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

        #expect(count >= 0)
    }

    @Test("Can enumerate ejectable volumes")
    func enumerateVolumes() async {
        let session = DiskSession.shared
        let volumes = await session.enumerateEjectableVolumes()

        #expect(volumes.count >= 0)

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

        #expect(count == volumes.count)
    }

    // MARK: - Eject Options

    @Test("Default eject options are correct")
    func defaultEjectOptions() {
        let options = EjectOptions.default

        #expect(!options.force)
        #expect(options.ejectPhysicalDevice)
    }

    @Test("Unmount-only options are correct")
    func unmountOnlyOptions() {
        let options = EjectOptions.unmountOnly

        #expect(!options.force)
        #expect(!options.ejectPhysicalDevice)
    }

    @Test("Force eject options are correct")
    func forceEjectOptions() {
        let options = EjectOptions.forceEject

        #expect(options.force)
        #expect(options.ejectPhysicalDevice)
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

        _ = result.totalCount
        _ = result.successCount
        _ = result.failedCount
        _ = result.results
        _ = result.totalDuration

        #expect(result.totalCount == result.successCount + result.failedCount)
    }

}

@Suite("Performance Tests")
struct PerformanceTests {

    @Test("Volume count is fast", .timeLimit(.minutes(1)))
    func volumeCountPerformance() async {
        let session = DiskSession.shared

        for _ in 0..<10 {
            _ = await session.ejectableVolumeCount()
        }
    }

    @Test("Full enumeration is reasonably fast", .timeLimit(.minutes(1)))
    func enumerationPerformance() async {
        let session = DiskSession.shared

        for _ in 0..<5 {
            _ = await session.enumerateEjectableVolumes()
        }
    }
}

@Suite("Real Hardware Tests", .disabled("Requires external volumes"))
struct RealHardwareTests {

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

        #expect(result.totalCount == volumes.count)
        #expect(result.successCount + result.failedCount == result.totalCount)
    }
}
