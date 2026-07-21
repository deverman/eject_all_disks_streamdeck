//
//  SwiftDiskArbitration.swift
//  SwiftDiskArbitration
//
//  A modern Swift wrapper for macOS DiskArbitration framework.
//
//  Features:
//  - Async/await APIs for disk operations
//  - Swift concurrency-friendly design (actors + async/await)
//  - No subprocess spawning (direct kernel communication)
//  - Typically faster than diskutil command-line tool
//  - Balanced retain/release for callback bridging
//
//  Usage:
//  ```swift
//  import SwiftDiskArbitration
//
//  // Quick ejection of all external drives
//  let result = await DiskSession.shared.ejectAllExternal()
//  print("Ejected \(result.successCount)/\(result.totalCount) volumes")
//
//  // Or with more control
//  let session = try DiskSession()
//  let volumes = session.enumerateEjectableVolumes()
//  for volume in volumes {
//      let result = await session.unmount(volume)
//      if !result.success {
//          print("Failed to eject \(volume.info.name): \(result.error!)")
//      }
//  }
//  ```
//

// Re-export all public types
@_exported import DiskArbitration

// MARK: - Convenience Functions

/// Enumerates all ejectable volumes using the shared session.
/// Returns an empty array if the shared session is unavailable.
/// - Returns: Array of volumes that can be ejected
public func enumerateEjectableVolumes() async -> [Volume] {
  guard let session = DiskSession.shared else { return [] }
  return await session.enumerateEjectableVolumes()
}

/// Returns the count of ejectable volumes.
/// Returns 0 if the shared session is unavailable.
/// - Returns: Number of external/ejectable volumes currently mounted
public func ejectableVolumeCount() async -> Int {
  guard let session = DiskSession.shared else { return 0 }
  return await session.ejectableVolumeCount()
}

/// Ejects all external volumes using the shared session.
/// Returns an empty failed batch if the shared session is unavailable.
/// - Parameter options: Options for the eject operation
/// - Returns: Result of the batch operation
public func ejectAllExternalVolumes(options: EjectOptions = .default) async -> BatchEjectResult {
  guard let session = DiskSession.shared else {
    return BatchEjectResult(
      totalCount: 0, successCount: 0, failedCount: 0, results: [], totalDuration: 0
    )
  }
  return await session.ejectAllExternal(options: options)
}

/// Ejects a single volume by path.
/// Fails with a session error if the shared session is unavailable.
/// - Parameters:
///   - path: Path to the volume mount point
///   - options: Options for the eject operation
/// - Returns: Result of the operation
public func ejectVolume(at path: String, options: EjectOptions = .default) async
  -> DiskOperationResult
{
  guard let session = DiskSession.shared else {
    return DiskOperationResult(success: false, error: .sessionCreationFailed, duration: 0)
  }
  return await session.unmount(path: path, options: options)
}

// MARK: - Version Info

/// Library version information
public enum SwiftDiskArbitrationVersion {
  public static let major = 1
  public static let minor = 0
  public static let patch = 0
  public static var string: String { "\(major).\(minor).\(patch)" }
}
