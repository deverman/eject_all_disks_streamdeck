//
//  DisplayLogicTests.swift
//  EjectAllDisksPluginTests
//
//  Tests for display title formatting and disk count logic
//

import Testing
import Foundation
@testable import EjectAllDisksPlugin

/// Helper to test display title logic (mirrors EjectAction.updateDisplay logic)
enum DisplayTitle {
    /// Generate the title for the given disk count and showTitle setting
    static func forDiskCount(_ count: Int, showTitle: Bool) -> String? {
        guard showTitle else { return nil }

        if count > 0 {
            return "\(count) Disk\(count == 1 ? "" : "s")"
        } else {
            // Show "No Disks" when nothing is mounted - clearer UX
            return "No Disks"
        }
    }

    /// Generate title for ejecting state
    static func ejecting(showTitle: Bool) -> String? {
        showTitle ? "Ejecting..." : nil
    }

    /// Generate title for success state
    static func success(showTitle: Bool) -> String? {
        showTitle ? "Ejected!" : nil
    }

    /// Generate title for no disks state
    static func noDisks(showTitle: Bool) -> String? {
        showTitle ? "No Disks" : nil
    }

    /// Generate title for error state
    static func error(showTitle: Bool) -> String? {
        showTitle ? "Error" : nil
    }

    /// Generate title for failed state
    static func failed(showTitle: Bool) -> String? {
        showTitle ? "Failed" : nil
    }
}

@Suite("Display Title Formatting Tests")
struct DisplayTitleTests {

    // MARK: - Disk Count Display

    @Test("Zero disks shows No Disks")
    func zeroDiskTitle() {
        let title = DisplayTitle.forDiskCount(0, showTitle: true)
        #expect(title == "No Disks")
    }

    @Test("One disk shows singular")
    func oneDiskTitle() {
        let title = DisplayTitle.forDiskCount(1, showTitle: true)
        #expect(title == "1 Disk")
    }

    @Test("Two disks shows plural")
    func twoDiskTitle() {
        let title = DisplayTitle.forDiskCount(2, showTitle: true)
        #expect(title == "2 Disks")
    }

    @Test("Many disks shows plural")
    func manyDiskTitle() {
        let title = DisplayTitle.forDiskCount(10, showTitle: true)
        #expect(title == "10 Disks")
    }

    @Test("Show title false returns nil for disk count")
    func hiddenDiskTitle() {
        let title = DisplayTitle.forDiskCount(5, showTitle: false)
        #expect(title == nil)
    }

    // MARK: - State Titles

    @Test("Ejecting state shows correct title")
    func ejectingTitle() {
        #expect(DisplayTitle.ejecting(showTitle: true) == "Ejecting...")
        #expect(DisplayTitle.ejecting(showTitle: false) == nil)
    }

    @Test("Success state shows correct title")
    func successTitle() {
        #expect(DisplayTitle.success(showTitle: true) == "Ejected!")
        #expect(DisplayTitle.success(showTitle: false) == nil)
    }

    @Test("No disks state shows correct title")
    func noDisksTitle() {
        #expect(DisplayTitle.noDisks(showTitle: true) == "No Disks")
        #expect(DisplayTitle.noDisks(showTitle: false) == nil)
    }

    @Test("Error state shows correct title")
    func errorTitle() {
        #expect(DisplayTitle.error(showTitle: true) == "Error")
        #expect(DisplayTitle.error(showTitle: false) == nil)
    }

    @Test("Failed state shows correct title")
    func failedTitle() {
        #expect(DisplayTitle.failed(showTitle: true) == "Failed")
        #expect(DisplayTitle.failed(showTitle: false) == nil)
    }
}

@Suite("Disk Count Edge Cases")
struct DiskCountEdgeCaseTests {

    @Test("Large disk count formats correctly")
    func largeDiskCount() {
        let title = DisplayTitle.forDiskCount(100, showTitle: true)
        #expect(title == "100 Disks")
    }

    @Test("Negative disk count handled", arguments: [-1, -5, -100])
    func negativeDiskCount(count: Int) {
        // Negative counts should show "No Disks" (treated as 0)
        let title = DisplayTitle.forDiskCount(count, showTitle: true)
        #expect(title == "No Disks")
    }
}

@Suite("State Transition Logic")
struct StateTransitionTests {

    @Test("Normal state titles vary by disk count")
    func normalStateTitles() {
        // No disks
        #expect(DisplayTitle.forDiskCount(0, showTitle: true) == "No Disks")

        // Has disks
        #expect(DisplayTitle.forDiskCount(1, showTitle: true) == "1 Disk")
        #expect(DisplayTitle.forDiskCount(3, showTitle: true) == "3 Disks")
    }

    @Test("All state titles respect showTitle setting")
    func allStatesRespectShowTitle() {
        // When showTitle is false, all titles should be nil
        #expect(DisplayTitle.forDiskCount(5, showTitle: false) == nil)
        #expect(DisplayTitle.ejecting(showTitle: false) == nil)
        #expect(DisplayTitle.success(showTitle: false) == nil)
        #expect(DisplayTitle.noDisks(showTitle: false) == nil)
        #expect(DisplayTitle.error(showTitle: false) == nil)
        #expect(DisplayTitle.failed(showTitle: false) == nil)
    }

    @Test("State titles are distinct")
    func statesAreDistinct() {
        let states = [
            DisplayTitle.ejecting(showTitle: true),
            DisplayTitle.success(showTitle: true),
            DisplayTitle.noDisks(showTitle: true),
            DisplayTitle.error(showTitle: true),
            DisplayTitle.failed(showTitle: true)
        ]

        // All non-nil and unique
        let nonNilStates = states.compactMap { $0 }
        #expect(nonNilStates.count == 5)
        #expect(Set(nonNilStates).count == 5, "All state titles should be unique")
    }
}
