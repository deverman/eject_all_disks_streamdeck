//
//  DiskEjectProgress.swift
//  SwiftDiskArbitration
//
//  Typed physical-device progress and failure context. These values deliberately
//  contain no user-visible volume names or paths so callers can safely route them
//  through logs and concurrency boundaries.
//

import DiskArbitration
import Foundation

/// Stable identity for one whole physical disk during an eject operation.
public struct PhysicalDeviceID: RawRepresentable, Sendable, Codable, Hashable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(bsdName: String) {
    self.rawValue = bsdName
  }

  /// BSD identifier such as `disk2`. This is safe for diagnostic logging.
  public var bsdName: String { rawValue }
}

/// The DiskArbitration stage that produced progress or an error.
public enum DiskOperationStage: String, Sendable, Codable, Hashable {
  case unmount
  case eject
}

/// Structured failure context retained for user feedback and future blocker
/// diagnostics. It intentionally does not identify processes or applications.
public struct DeviceEjectFailure: Sendable, Equatable {
  public let deviceID: PhysicalDeviceID
  public let stage: DiskOperationStage
  public let category: DiskErrorCategory
  public let rawStatus: DAReturn?

  public init(
    deviceID: PhysicalDeviceID,
    stage: DiskOperationStage,
    category: DiskErrorCategory,
    rawStatus: DAReturn?
  ) {
    self.deviceID = deviceID
    self.stage = stage
    self.category = category
    self.rawStatus = rawStatus
  }
}

/// Terminal state for one whole physical device.
public enum DeviceEjectOutcome: Sendable, Equatable {
  /// Whole-disk unmount and physical eject were both confirmed by callbacks.
  case safeToRemove(duration: TimeInterval)

  /// Unmount-only API completed successfully. This is not safe-to-remove proof.
  case unmounted(duration: TimeInterval)

  /// DiskArbitration returned a definitive dissenter.
  case failed(DeviceEjectFailure, duration: TimeInterval)

  /// SafeEject stopped waiting without confirmation at the named stage.
  case timedOut(stage: DiskOperationStage, duration: TimeInterval)

  /// The Swift caller stopped waiting. DiskArbitration itself cannot be cancelled.
  case cancelled(stage: DiskOperationStage, duration: TimeInterval)
}

/// Progress emitted independently by every physical device in a batch.
public enum DeviceEjectEvent: Sendable, Equatable {
  case unmountStarted(PhysicalDeviceID)
  case unmountCompleted(PhysicalDeviceID)
  case ejectStarted(PhysicalDeviceID)
  case completed(PhysicalDeviceID, DeviceEjectOutcome)
}
