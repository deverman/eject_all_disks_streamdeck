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
      #expect(
        error.description.lowercased().contains(expectedSubstring),
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
    let busyError = DiskError.from(status: Int32(bitPattern: 0xF8DA_0002), message: "test")
    if case .busy(let message) = busyError {
      #expect(message == "test")
    } else {
      Issue.record("Expected .busy error")
    }

    let notFoundError = DiskError.from(status: Int32(bitPattern: 0xF8DA_0006), message: nil)
    if case .notFound = notFoundError {
      // Success
    } else {
      Issue.record("Expected .notFound error")
    }
  }

  @Test("Unknown status codes produce .unknown error")
  func unknownStatusCode() {
    let raw = Int32(bitPattern: 0x1234_5678)
    let error = DiskError.from(status: raw, message: "weird error")
    if case .unknown(let status, let message) = error {
      #expect(status == raw)
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

@Suite("DiskError Category Tests")
struct DiskErrorCategoryTests {

  @Test("Permission errors map to .permission")
  func permissionCategory() {
    #expect(DiskError.notPermitted(message: nil).category == .permission)
    #expect(DiskError.notPrivileged(message: nil).category == .permission)
  }

  @Test("Busy errors map to .busy")
  func busyCategory() {
    #expect(DiskError.busy(message: nil).category == .busy)
    #expect(DiskError.exclusiveAccess(message: nil).category == .busy)
  }

  @Test("Timeout maps to .timeout")
  func timeoutCategory() {
    #expect(DiskError.timeout.category == .timeout)
  }

  @Test("Session failure maps to .session")
  func sessionCategory() {
    #expect(DiskError.sessionCreationFailed.category == .session)
  }

  @Test("General and unknown errors map to .other")
  func otherCategory() {
    #expect(DiskError.generalError(message: nil).category == .other)
    #expect(DiskError.unknown(status: 42, message: nil).category == .other)
  }

  @Test("Category raw values are log-safe identifiers")
  func rawValues() {
    #expect(DiskErrorCategory.permission.rawValue == "permission")
    #expect(DiskErrorCategory.busy.rawValue == "busy")
    #expect(DiskErrorCategory.timeout.rawValue == "timeout")
  }
}

@Suite("Callback Context Tests")
struct DiskCallbackContextTests {

  @Test("Continuation resumes exactly once when raced")
  func resumeOnce() async {
    let result: DiskOperationResult = await withCheckedContinuation { continuation in
      let context = DiskCallbackContext(continuation: continuation)
      let first = context.resume(
        with: DiskOperationResult(success: true, error: nil, duration: 0.1)
      )
      let second = context.resume(
        with: DiskOperationResult(success: false, error: .timeout, duration: 0.2)
      )
      #expect(first, "First resume should win")
      #expect(!second, "Second resume should be dropped")
    }

    #expect(result.success, "The first (winning) result should be delivered")
    #expect(result.error == nil)
  }
}
