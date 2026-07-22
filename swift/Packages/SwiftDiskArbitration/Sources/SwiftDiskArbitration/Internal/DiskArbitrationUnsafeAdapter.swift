//
//  DiskArbitrationUnsafeAdapter.swift
//  SwiftDiskArbitration
//
//  The narrow audited boundary for DiskArbitration's C pointers and callbacks.
//  Context pointers encode integers only and are never dereferenced.
//

import DiskArbitration
import Foundation

internal enum DiskArbitrationUnsafeAdapter {
  private static let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
    unsafe finishCallback(context: context, dissenter: dissenter)
  }

  private static let ejectCallback: DADiskEjectCallback = { _, dissenter, context in
    unsafe finishCallback(context: context, dissenter: dissenter)
  }

  /// The only C callback entry point. It decodes the cookie without
  /// dereferencing it, copies dissenter data, then completes through the
  /// registry's exactly-once race.
  private static func finishCallback(
    context: UnsafeMutableRawPointer?,
    dissenter: DADissenter?
  ) {
    guard let token = unsafe token(from: context) else { return }
    let result = dissenterResult(dissenter)
    DiskOperationRegistry.shared.completeFromCallback(
      token: token,
      error: result.error,
      rawStatus: result.rawStatus
    )
  }

  /// Encodes a nonzero integer as an opaque cookie. DiskArbitration echoes this
  /// bit pattern to the callback; it does not point at allocated memory.
  internal static func contextPointer(for token: UInt) -> UnsafeMutableRawPointer {
    precondition(token != 0)
    guard let pointer = unsafe UnsafeMutableRawPointer(bitPattern: token) else {
      preconditionFailure("Nonzero disk operation token could not form a context pointer")
    }
    return unsafe pointer
  }

  /// Decodes the opaque integer cookie without dereferencing it.
  internal static func token(from context: UnsafeMutableRawPointer?) -> UInt? {
    guard let context = unsafe context else { return nil }
    let token = UInt(bitPattern: context)
    return token == 0 ? nil : token
  }

  internal static func dissenterResult(
    _ dissenter: DADissenter?
  ) -> (error: DiskError?, rawStatus: DAReturn?) {
    guard let dissenter else { return (nil, nil) }
    let status = DADissenterGetStatus(dissenter)
    let message = DADissenterGetStatusString(dissenter).map { $0 as String }
    return (DiskError.from(status: status, message: message), status)
  }

  internal static func submitUnmount(
    _ disk: DADisk,
    options: DADiskUnmountOptions,
    token: UInt
  ) {
    unsafe DADiskUnmount(disk, options, unmountCallback, contextPointer(for: token))
  }

  internal static func submitEject(
    _ disk: DADisk,
    options: DADiskEjectOptions,
    token: UInt
  ) {
    unsafe DADiskEject(disk, options, ejectCallback, contextPointer(for: token))
  }

  /// Copies the DiskArbitration-owned C string before returning to the caller.
  internal static func bsdName(of disk: DADisk) -> String? {
    guard let name = unsafe DADiskGetBSDName(disk) else { return nil }
    return unsafe String(cString: name)
  }
}
