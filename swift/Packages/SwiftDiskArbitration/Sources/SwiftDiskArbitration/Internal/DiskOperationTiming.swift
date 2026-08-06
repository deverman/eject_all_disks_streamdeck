//
//  DiskOperationTiming.swift
//  SwiftDiskArbitration
//
//  Absolute, monotonic operation deadlines. Wall-clock time is intentionally
//  absent because user or network clock changes must not extend an eject.
//

import Foundation

internal let diskOperationTimeout: Duration = .seconds(30)
internal let wholeDiskUnmountTimeout: Duration = .seconds(25)

internal struct DeviceOperationDeadlines<C: Clock>: Sendable
where C.Duration == Duration, C.Instant: Sendable {
  let startedAt: C.Instant
  let unmountDeadline: C.Instant
  let overallDeadline: C.Instant

  init(
    startedAt: C.Instant,
    unmountTimeout: Duration = wholeDiskUnmountTimeout,
    overallTimeout: Duration = diskOperationTimeout
  ) {
    self.startedAt = startedAt
    self.unmountDeadline = startedAt.advanced(by: min(unmountTimeout, overallTimeout))
    self.overallDeadline = startedAt.advanced(by: overallTimeout)
  }
}

extension Duration {
  /// Converts a monotonic duration to the legacy public `TimeInterval` field.
  internal var diskOperationTimeInterval: TimeInterval {
    let parts = components
    let seconds = Double(parts.seconds)
    let fractional = Double(parts.attoseconds) / 1_000_000_000_000_000_000
    return max(0, seconds + fractional)
  }
}
