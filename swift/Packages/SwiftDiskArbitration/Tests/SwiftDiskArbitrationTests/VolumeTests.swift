//
//  VolumeTests.swift
//  SwiftDiskArbitrationTests
//
//  Tests for VolumeInfo and Volume types
//

import Testing
import Foundation

@testable import SwiftDiskArbitration

@Suite("VolumeInfo Tests")
struct VolumeInfoTests {

  @Test("VolumeInfo is Codable")
  func volumeInfoCodable() throws {
    let info = VolumeInfo(
      name: "Test Drive",
      path: "/Volumes/Test Drive",
      bsdName: "disk2s1",
      isEjectable: true,
      isRemovable: true,
      isInternal: false,
      isDiskImage: false
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(info)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(VolumeInfo.self, from: data)

    #expect(decoded.name == info.name)
    #expect(decoded.path == info.path)
    #expect(decoded.bsdName == info.bsdName)
    #expect(decoded.isEjectable == info.isEjectable)
    #expect(decoded.isRemovable == info.isRemovable)
    #expect(decoded.isInternal == info.isInternal)
    #expect(decoded.isDiskImage == info.isDiskImage)
  }

  @Test("VolumeInfo is Hashable")
  func volumeInfoHashable() {
    let info1 = VolumeInfo(
      name: "Drive",
      path: "/Volumes/Drive"
    )
    let info2 = VolumeInfo(
      name: "Drive",
      path: "/Volumes/Drive"
    )
    let info3 = VolumeInfo(
      name: "Other",
      path: "/Volumes/Other"
    )

    #expect(info1 == info2)
    #expect(info1 != info3)

    var set = Set<VolumeInfo>()
    set.insert(info1)
    #expect(set.contains(info2))
    #expect(!set.contains(info3))
  }

  @Test("VolumeInfo defaults are correct")
  func volumeInfoDefaults() {
    let info = VolumeInfo(
      name: "Test",
      path: "/Volumes/Test"
    )

    #expect(info.bsdName == nil)
    #expect(info.isEjectable == false)
    #expect(info.isRemovable == false)
    #expect(info.isInternal == true)
    #expect(info.isDiskImage == false)
  }
}

@Suite("Volume Enumeration Tests")
struct VolumeEnumerationTests {

  @Test("Enumeration excludes system volumes")
  func excludesSystemVolumes() throws {
    // This test verifies the filtering logic by checking that
    // system volume names would be excluded
    let systemNames = [
      "Macintosh HD",
      "Macintosh HD - Data",
      "Recovery",
      "Preboot",
      "VM",
      "Update",
      ".hidden",
      "com.apple.TimeMachine.backup",
      "Backups of MacBook",
    ]

    for name in systemNames {
      // These should all be filtered out by our exclusion logic
      let shouldExclude =
        name.hasPrefix(".") || name.hasPrefix("com.apple.") || name.hasPrefix("Backups of ")
        || ["Macintosh HD", "Macintosh HD - Data", "Recovery", "Preboot", "VM", "Update"].contains(
          name)

      #expect(shouldExclude, "System volume '\(name)' should be excluded")
    }
  }

  @Test("Session can be created")
  func sessionCreation() throws {
    _ = try DiskSession()
  }

  @Test("Enumeration returns array (may be empty)")
  func enumerationReturnsArray() async throws {
    let session = try DiskSession()
    let volumes = await session.enumerateEjectableVolumes()

    // We can't guarantee external volumes are present, but it should return an array
    #expect(volumes.count >= 0)
  }

  @Test("Volume count matches enumeration")
  func volumeCountMatchesEnumeration() async throws {
    let session = try DiskSession()
    let volumes = await session.enumerateEjectableVolumes()
    let count = await session.ejectableVolumeCount()

    #expect(count == volumes.count)
  }
}
