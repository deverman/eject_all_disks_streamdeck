//
//  Volume.swift
//  SwiftDiskArbitration
//
//  Represents an external volume with its associated DADisk reference.
//
// ============================================================================
// SWIFT BEGINNER'S GUIDE TO THIS FILE
// ============================================================================
//
// WHAT THIS FILE DOES:
// --------------------
// Finds all ejectable drives (USB drives, SD cards, disk images) and creates
// Volume objects that we can later eject.
//
// KEY CONCEPTS:
// -------------
//
// 1. DADisk (DiskArbitration Disk)
//    This is Apple's C type representing a disk. Think of it as a "handle"
//    that lets us tell macOS "please eject THIS specific drive."
//    We cache it to avoid looking it up again when ejecting.
//
// 2. WHY @unchecked Sendable?
//    Swift 6 requires types passed between threads to be "Sendable" (safe).
//    DADisk is a C type that Swift doesn't know is thread-safe.
//    We mark Volume as `@unchecked Sendable` to tell Swift:
//    "Trust us, this is safe to use from multiple threads."
//
//    This is safe because:
//    - VolumeInfo is immutable (can't change after creation)
//    - DADisk is read-only after we create it
//    - We only use it for eject operations (which are thread-safe)
//
// 3. WHOLE DISK vs VOLUME
//    A physical USB drive might have multiple partitions:
//
//      USB Drive (disk2)          ← "whole disk" (physical device)
//        ├── Partition 1 (disk2s1)  ← volume
//        └── Partition 2 (disk2s2)  ← volume
//
//    To physically eject the USB, we need the "whole disk" reference.
//    That's why we cache `wholeDisk` - it's the physical device to eject.
//
// 4. VOLUME ENUMERATION LOGIC (SECURITY)
//    We scan /Volumes and use SYSTEM APIs to filter safely:
//    - Use .volumeIsRootFileSystemKey to detect boot volume (not name!)
//    - Use .volumeIsBrowsableKey to detect system-only volumes
//    - Use DiskArbitration properties as additional safety check
//    - Include if: external OR ejectable OR removable
//
//    WHY NOT USE VOLUME NAMES?
//    Users can rename "Macintosh HD" to anything they want.
//    If we filtered by name, we might accidentally eject the boot drive!
//
// ============================================================================

import DiskArbitration
import Foundation

/// Information about a mounted volume.
public struct VolumeInfo: Sendable, Codable, Hashable {
  /// Display name of the volume (e.g., "My USB Drive")
  public let name: String

  /// Full path to the mount point (e.g., "/Volumes/My USB Drive")
  public let path: String

  /// BSD device name (e.g., "disk2s1")
  public let bsdName: String?

  /// Whether the system reports this volume as ejectable
  public let isEjectable: Bool

  /// Whether the system reports this volume as removable media
  public let isRemovable: Bool

  /// Whether this is an internal drive
  public let isInternal: Bool

  /// Whether this is a disk image (.dmg)
  public let isDiskImage: Bool

  public init(
    name: String,
    path: String,
    bsdName: String? = nil,
    isEjectable: Bool = false,
    isRemovable: Bool = false,
    isInternal: Bool = true,
    isDiskImage: Bool = false
  ) {
    self.name = name
    self.path = path
    self.bsdName = bsdName
    self.isEjectable = isEjectable
    self.isRemovable = isRemovable
    self.isInternal = isInternal
    self.isDiskImage = isDiskImage
  }
}

/// A volume with its associated DADisk reference for direct DiskArbitration operations.
/// This type caches the DADisk reference to avoid recreation overhead during ejection.
///
/// Thread Safety: This type is marked @unchecked Sendable because:
/// - VolumeInfo is immutable and Sendable
/// - DADisk (CFType) is thread-safe for read operations after creation
/// - The disk reference is only used for unmount/eject operations which are thread-safe
public final class Volume: @unchecked Sendable {
  /// Information about this volume
  public let info: VolumeInfo

  /// The cached DADisk reference for this volume
  /// This avoids the overhead of calling DADiskCreateFromVolumePath during ejection
  internal let disk: DADisk

  /// The whole-disk reference (for multi-partition devices)
  /// Cached lazily when needed for ejection
  internal private(set) var wholeDisk: DADisk?

  /// URL for the volume mount point
  public var url: URL {
    URL(fileURLWithPath: info.path)
  }

  /// Creates a Volume from volume info and a pre-created DADisk reference
  /// - Parameters:
  ///   - info: The volume information
  ///   - disk: The DADisk reference (will be retained)
  internal init(info: VolumeInfo, disk: DADisk) {
    self.info = info
    self.disk = disk
    // Pre-cache the whole disk reference
    self.wholeDisk = DADiskCopyWholeDisk(disk)
  }

  deinit {
    // DADisk is a CFType, Swift handles release via ARC
    // wholeDisk is also managed by ARC
  }

  /// Returns the BSD name of the whole disk (physical device).
  /// For example, if this volume is "disk2s1", returns "disk2"
  /// Returns nil if the whole disk reference is not available
  internal var wholeDiskBSDName: String? {
    guard let wholeDisk = wholeDisk,
      let bsdName = DADiskGetBSDName(wholeDisk)
    else {
      return nil
    }
    return String(cString: bsdName)
  }
}

// MARK: - Volume Discovery

extension Volume {
  /// Enumerates all ejectable external volumes.
  ///
  /// SECURITY: This method uses macOS system APIs to detect system volumes,
  /// NOT hardcoded volume names. This ensures safety even if the user has
  /// renamed their boot drive.
  ///
  /// A volume is included if ALL of these are true:
  /// - NOT the root filesystem (boot volume)
  /// - NOT a system volume (Recovery, Preboot, VM, etc.)
  /// - NOT an internal non-ejectable drive
  /// - IS external OR ejectable OR removable
  ///
  /// Each returned Volume includes a cached DADisk reference for fast ejection.
  ///
  /// - Parameter session: The DiskArbitration session to use
  /// - Returns: Array of ejectable volumes with cached disk references
  public static func enumerateEjectableVolumes(session: DASession) -> [Volume] {
    let fileManager = FileManager.default
    let volumesPath = "/Volumes"

    guard let contents = try? fileManager.contentsOfDirectory(atPath: volumesPath) else {
      return []
    }

    var volumes: [Volume] = []

    for name in contents {
      // Skip hidden files (e.g., .timemachine, .Spotlight-V100)
      guard !name.hasPrefix(".") else { continue }

      // Skip Apple system volumes by prefix (these are internal system things)
      guard !name.hasPrefix("com.apple.") else { continue }

      // Skip Time Machine local snapshots
      guard !name.hasPrefix("Backups of ") else { continue }

      let path = "\(volumesPath)/\(name)"
      let url = URL(fileURLWithPath: path)

      // Verify it's a directory (mount point)
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        continue
      }

      // =====================================================================
      // SECURITY: Use system APIs to detect protected volumes
      // This is safer than matching volume names, which users can change.
      // =====================================================================

      // Get volume properties from the filesystem using URL resource values
      // These are the authoritative source for volume characteristics
      let resourceKeys: Set<URLResourceKey> = [
        .volumeIsRootFileSystemKey,    // Is this the boot volume?
        .volumeIsEjectableKey,         // Can this be ejected?
        .volumeIsRemovableKey,         // Is this removable media?
        .volumeIsInternalKey,          // Is this an internal drive?
        .volumeIsLocalKey,             // Is this a local (not network) volume?
        .volumeIsBrowsableKey,         // Is this browsable by users?
      ]

      guard let resourceValues = try? url.resourceValues(forKeys: resourceKeys) else {
        continue
      }

      // CRITICAL: Never eject the root filesystem (boot volume)
      // This check works regardless of what the user named their drive
      let isRootFileSystem = resourceValues.volumeIsRootFileSystem ?? false
      guard !isRootFileSystem else {
        continue
      }

      // Skip non-browsable volumes (system-only volumes like Preboot, Recovery)
      // These are not meant to be user-accessible and should never be ejected
      let isBrowsable = resourceValues.volumeIsBrowsable ?? true
      guard isBrowsable else {
        continue
      }

      let isEjectable = resourceValues.volumeIsEjectable ?? false
      let isRemovable = resourceValues.volumeIsRemovable ?? false
      let isInternal = resourceValues.volumeIsInternal ?? true

      // Include if: ejectable OR removable OR external
      // Internal non-ejectable drives (like a second internal SSD) are excluded
      guard isEjectable || isRemovable || !isInternal else {
        continue
      }

      // Create DADisk reference from the volume path
      // This is cached for later use during ejection
      guard
        let disk = DADiskCreateFromVolumePath(
          kCFAllocatorDefault,
          session,
          url as CFURL
        )
      else {
        continue
      }

      // Additional safety check using DiskArbitration properties
      // This catches edge cases the URL resource values might miss
      if isSystemVolume(disk: disk) {
        continue
      }

      // Get BSD name from the disk
      var bsdName: String? = nil
      if let bsdNameCStr = DADiskGetBSDName(disk) {
        bsdName = String(cString: bsdNameCStr)
      }

      // Check if it's a disk image
      let isDiskImage = checkIfDiskImage(disk: disk)

      let info = VolumeInfo(
        name: name,
        path: path,
        bsdName: bsdName,
        isEjectable: isEjectable,
        isRemovable: isRemovable,
        isInternal: isInternal,
        isDiskImage: isDiskImage
      )

      volumes.append(Volume(info: info, disk: disk))
    }

    return volumes
  }

  /// Checks if a disk is a system volume using DiskArbitration properties.
  /// This provides an additional layer of protection beyond URL resource values.
  private static func isSystemVolume(disk: DADisk) -> Bool {
    guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
      // If we can't get the description, be conservative and skip it
      return true
    }

    // Note: kDADiskDescriptionVolumeKindKey indicates filesystem type (apfs, hfs, etc.)
    // but doesn't distinguish system from user volumes, so we rely on other checks

    // Check the volume roles - system volumes have specific roles
    // This is available on APFS volumes
    if let mediaContent = description[kDADiskDescriptionMediaContentKey as String] as? String {
      // Apple_APFS_Recovery, Apple_Boot, etc. are system partitions
      let systemContentTypes = [
        "Apple_Boot",
        "Apple_APFS_Recovery",
        "Apple_APFS_ISC",
        "Apple_KernelCoreDump",
      ]
      if systemContentTypes.contains(mediaContent) {
        return true
      }
    }

    // Check if the volume is not mountable by users (system-only)
    if let isMountable = description[kDADiskDescriptionVolumeMountableKey as String] as? Bool {
      if !isMountable {
        return true
      }
    }

    return false
  }

  /// Checks if a disk is a disk image (.dmg)
  private static func checkIfDiskImage(disk: DADisk) -> Bool {
    guard let description = DADiskCopyDescription(disk) as? [String: Any] else {
      return false
    }

    // Check the device model key for "Disk Image"
    if let model = description[kDADiskDescriptionDeviceModelKey as String] as? String {
      return model == "Disk Image"
    }

    return false
  }
}

// MARK: - CustomStringConvertible

extension Volume: CustomStringConvertible {
  public var description: String {
    var flags: [String] = []
    if info.isEjectable { flags.append("ejectable") }
    if info.isRemovable { flags.append("removable") }
    if !info.isInternal { flags.append("external") }
    if info.isDiskImage { flags.append("disk-image") }

    let flagsStr = flags.isEmpty ? "none" : flags.joined(separator: ", ")
    return "Volume(\"\(info.name)\", bsd: \(info.bsdName ?? "?"), flags: [\(flagsStr)])"
  }
}
