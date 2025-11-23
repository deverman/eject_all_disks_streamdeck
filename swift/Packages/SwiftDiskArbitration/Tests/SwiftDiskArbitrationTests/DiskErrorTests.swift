//
//  DiskErrorTests.swift
//  SwiftDiskArbitrationTests
//
//  Tests for DiskError type and DAReturn conversion
//

import Testing
@testable import SwiftDiskArbitration

@Suite("DiskError Tests")
struct DiskErrorTests {

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [(DiskError, String)] = [
            (.busy(message: nil), "busy"),
            (.notFound(message: nil), "not found"),
            (.notPermitted(message: nil), "not permitted"),
            (.notMounted(message: nil), "not mounted"),
        ]

        for (error, expectedSubstring) in errors {
            #expect(error.description.lowercased().contains(expectedSubstring),
                   "Error description should contain '\(expectedSubstring)'")
        }
    }

    @Test("Custom messages are included in description")
    func customMessages() {
        let error = DiskError.busy(message: "Spotlight indexing")
        #expect(error.description.contains("Spotlight indexing"))
    }

    @Test("isDiskBusy returns correct values")
    func isDiskBusyProperty() {
        #expect(DiskError.busy(message: nil).isDiskBusy)
        #expect(DiskError.exclusiveAccess(message: nil).isDiskBusy)
        #expect(!DiskError.notFound(message: nil).isDiskBusy)
        #expect(!DiskError.notPermitted(message: nil).isDiskBusy)
    }

    @Test("DAReturn conversion handles known codes")
    func daReturnConversion() {
        // Test known status codes
        let busyError = DiskError.from(status: 0xF8DA0002, message: "test")
        if case .busy(let message) = busyError {
            #expect(message == "test")
        } else {
            Issue.record("Expected .busy error")
        }

        let notFoundError = DiskError.from(status: 0xF8DA0006, message: nil)
        if case .notFound = notFoundError {
            // Success
        } else {
            Issue.record("Expected .notFound error")
        }
    }

    @Test("Unknown status codes produce .unknown error")
    func unknownStatusCode() {
        let error = DiskError.from(status: 0x12345678, message: "weird error")
        if case .unknown(let status, let message) = error {
            #expect(status == 0x12345678)
            #expect(message == "weird error")
        } else {
            Issue.record("Expected .unknown error")
        }
    }

    @Test("Success status returns .success")
    func successStatus() {
        let error = DiskError.from(status: 0, message: nil)
        if case .success = error {
            // Success
        } else {
            Issue.record("Expected .success")
        }
    }

    @Test("Nil dissenter returns nil error")
    func nilDissenter() {
        let error = DiskError.from(dissenter: nil)
        #expect(error == nil)
    }
}
