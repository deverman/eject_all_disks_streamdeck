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

// MARK: - Error Title Formatting (typed categories)

import SwiftDiskArbitration

/// Builds a BatchEjectResult from per-volume (success, category) pairs.
private func makeBatchResult(_ outcomes: [(success: Bool, category: DiskErrorCategory?)]) -> BatchEjectResult {
    let results = outcomes.enumerated().map { index, outcome in
        SingleEjectResult(
            volumeName: "Volume\(index)",
            volumePath: "/Volumes/Volume\(index)",
            bsdName: "disk\(index + 2)s1",
            success: outcome.success,
            errorMessage: outcome.success ? nil : "error",
            errorCategory: outcome.category,
            duration: 0.1
        )
    }
    let successCount = results.filter(\.success).count
    return BatchEjectResult(
        totalCount: results.count,
        successCount: successCount,
        failedCount: results.count - successCount,
        results: results,
        totalDuration: 0.5
    )
}

@Suite("Error Title Formatting Tests")
struct ErrorTitleFormattingTests {

    @Test("All permission failures suggest granting access")
    func allPermissionFailures() {
        let result = makeBatchResult([
            (false, .permission),
            (false, .permission),
        ])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "Grant\nAccess")
    }

    @Test("Mixed failure categories do not suggest granting access")
    func mixedFailures() {
        let result = makeBatchResult([
            (false, .permission),
            (false, .busy),
        ])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "All Failed")
    }

    @Test("Single busy failure shows In Use")
    func singleBusyFailure() {
        let result = makeBatchResult([(false, .busy)])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "In Use")
    }

    @Test("Single timeout failure shows Timeout")
    func singleTimeoutFailure() {
        let result = makeBatchResult([(false, .timeout)])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "Timeout")
    }

    @Test("Single unclassified failure shows Failed")
    func singleUnknownFailure() {
        let result = makeBatchResult([(false, nil)])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "Failed")
    }

    @Test("Partial failure shows X of Y")
    func partialFailure() {
        let result = makeBatchResult([
            (true, nil),
            (true, nil),
            (false, .busy),
        ])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: true) == "1 of 3\nFailed")
    }

    @Test("Hidden title returns nil even on failure")
    func hiddenTitle() {
        let result = makeBatchResult([(false, .permission)])
        #expect(EjectAction.formatErrorTitle(result: result, showTitle: false) == nil)
    }
}
