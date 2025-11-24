//
//  DiskError.swift
//  SwiftDiskArbitration
//
//  Provides Swift-native error types for DiskArbitration operations.
//

import DiskArbitration
import Foundation

/// Errors that can occur during disk operations.
public enum DiskError: Error, Sendable, CustomStringConvertible {
  /// Operation succeeded (should not be thrown, used internally)
  case success

  /// General error with no specific cause
  case generalError(message: String?)

  /// The disk or resource is busy (files open, processes accessing)
  case busy(message: String?)

  /// Invalid argument provided to the operation
  case badArgument(message: String?)

  /// Exclusive access is required for this operation
  case exclusiveAccess(message: String?)

  /// Insufficient system resources
  case noResources(message: String?)

  /// The disk or volume was not found
  case notFound(message: String?)

  /// The volume is not currently mounted
  case notMounted(message: String?)

  /// Operation not permitted (security/sandbox restriction)
  case notPermitted(message: String?)

  /// Insufficient privileges (needs admin rights)
  case notPrivileged(message: String?)

  /// The device is not ready
  case notReady(message: String?)

  /// The media is read-only
  case notWritable(message: String?)

  /// The operation is not supported for this disk type
  case unsupported(message: String?)

  /// Unknown error with raw status code
  case unknown(status: DAReturn, message: String?)

  /// Failed to create a DiskArbitration session
  case sessionCreationFailed

  /// The disk reference is invalid or was deallocated
  case invalidDiskReference

  /// Operation timed out
  case timeout

  /// Operation was cancelled
  case cancelled

  /// Authorization failed (user denied or system error)
  case authorizationFailed(status: Int32)

  /// Not authorized to perform unmount operations
  case notAuthorized

  /// User cancelled the authorization dialog
  case authorizationCancelled

  public var description: String {
    switch self {
    case .success:
      return "Operation succeeded"
    case .generalError(let message):
      return "Disk error: \(message ?? "Unknown")"
    case .busy(let message):
      return "Disk busy: \(message ?? "Resource is in use")"
    case .badArgument(let message):
      return "Bad argument: \(message ?? "Invalid parameter")"
    case .exclusiveAccess(let message):
      return "Exclusive access required: \(message ?? "Another process has exclusive access")"
    case .noResources(let message):
      return "No resources: \(message ?? "Insufficient system resources")"
    case .notFound(let message):
      return "Not found: \(message ?? "Disk or volume not found")"
    case .notMounted(let message):
      return "Not mounted: \(message ?? "Volume is not mounted")"
    case .notPermitted(let message):
      return "Not permitted: \(message ?? "Operation not allowed")"
    case .notPrivileged(let message):
      return "Not privileged: \(message ?? "Requires administrator privileges")"
    case .notReady(let message):
      return "Not ready: \(message ?? "Device is not ready")"
    case .notWritable(let message):
      return "Not writable: \(message ?? "Media is read-only")"
    case .unsupported(let message):
      return "Unsupported: \(message ?? "Operation not supported")"
    case .unknown(let status, let message):
      return "Unknown error (0x\(String(status, radix: 16))): \(message ?? "No details")"
    case .sessionCreationFailed:
      return "Failed to create DiskArbitration session"
    case .invalidDiskReference:
      return "Invalid or deallocated disk reference"
    case .timeout:
      return "Operation timed out"
    case .cancelled:
      return "Operation was cancelled"
    case .authorizationFailed(let status):
      return "Authorization failed (status: \(status))"
    case .notAuthorized:
      return "Not authorized to unmount volumes. Call requestAuthorization() first."
    case .authorizationCancelled:
      return "User cancelled the authorization dialog"
    }
  }

  /// Whether this error indicates the disk is in use by another process
  public var isDiskBusy: Bool {
    switch self {
    case .busy, .exclusiveAccess:
      return true
    default:
      return false
    }
  }
}

// MARK: - DAReturn to DiskError Conversion

extension DiskError {
  /// Known DAReturn status codes
  /// These match the values in DADissenter.h
  /// DAReturn is Int32, so we use Int32(bitPattern:) to convert from the UInt32 hex representation
  private static let kDAReturnSuccess: DAReturn = 0
  private static let kDAReturnError: DAReturn = Int32(bitPattern: 0xF8DA_0001)
  private static let kDAReturnBusy: DAReturn = Int32(bitPattern: 0xF8DA_0002)
  private static let kDAReturnBadArgument: DAReturn = Int32(bitPattern: 0xF8DA_0003)
  private static let kDAReturnExclusiveAccess: DAReturn = Int32(bitPattern: 0xF8DA_0004)
  private static let kDAReturnNoResources: DAReturn = Int32(bitPattern: 0xF8DA_0005)
  private static let kDAReturnNotFound: DAReturn = Int32(bitPattern: 0xF8DA_0006)
  private static let kDAReturnNotMounted: DAReturn = Int32(bitPattern: 0xF8DA_0007)
  private static let kDAReturnNotPermitted: DAReturn = Int32(bitPattern: 0xF8DA_0008)
  private static let kDAReturnNotPrivileged: DAReturn = Int32(bitPattern: 0xF8DA_0009)
  private static let kDAReturnNotReady: DAReturn = Int32(bitPattern: 0xF8DA_000A)
  private static let kDAReturnNotWritable: DAReturn = Int32(bitPattern: 0xF8DA_000B)
  private static let kDAReturnUnsupported: DAReturn = Int32(bitPattern: 0xF8DA_000C)

  /// Creates a DiskError from a DADissenter object
  /// - Parameter dissenter: The dissenter returned from a DiskArbitration callback
  /// - Returns: A corresponding DiskError, or nil if dissenter is nil (success)
  public static func from(dissenter: DADissenter?) -> DiskError? {
    guard let dissenter = dissenter else {
      return nil  // nil dissenter means success
    }

    let status = DADissenterGetStatus(dissenter)
    let statusString: String? = {
      if let cfString = DADissenterGetStatusString(dissenter) {
        return cfString as String
      }
      return nil
    }()

    return from(status: status, message: statusString)
  }

  /// Creates a DiskError from a DAReturn status code
  /// - Parameters:
  ///   - status: The DAReturn status code
  ///   - message: Optional human-readable message
  /// - Returns: A corresponding DiskError
  public static func from(status: DAReturn, message: String?) -> DiskError {
    switch status {
    case kDAReturnSuccess:
      return .success
    case kDAReturnError:
      return .generalError(message: message)
    case kDAReturnBusy:
      return .busy(message: message)
    case kDAReturnBadArgument:
      return .badArgument(message: message)
    case kDAReturnExclusiveAccess:
      return .exclusiveAccess(message: message)
    case kDAReturnNoResources:
      return .noResources(message: message)
    case kDAReturnNotFound:
      return .notFound(message: message)
    case kDAReturnNotMounted:
      return .notMounted(message: message)
    case kDAReturnNotPermitted:
      return .notPermitted(message: message)
    case kDAReturnNotPrivileged:
      return .notPrivileged(message: message)
    case kDAReturnNotReady:
      return .notReady(message: message)
    case kDAReturnNotWritable:
      return .notWritable(message: message)
    case kDAReturnUnsupported:
      return .unsupported(message: message)
    default:
      return .unknown(status: status, message: message)
    }
  }
}
