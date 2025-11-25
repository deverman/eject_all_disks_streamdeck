# Implement Special Handling for Disk Images (.dmg)

## Problem

Disk images (`.dmg` files) sometimes fail to eject using DiskArbitration APIs even when running with `sudo` and Full Disk Access permissions. The error is typically:

```
Not privileged: Requires administrator privileges
```

This is a known macOS security issue where DiskArbitration APIs are restricted for disk images, but the native `hdiutil detach` command works reliably.

## Solution

Add special handling for disk images to use `hdiutil detach` instead of DiskArbitration APIs when ejecting volumes that are identified as disk images.

## Implementation Requirements

### 1. Detect Disk Images

The code already detects disk images in `Volume.swift`:
- `Volume.info.isDiskImage` boolean flag is set during enumeration
- Detection happens in `checkIfDiskImage(disk:)` at line 221

### 2. Add `hdiutil detach` Support

Create a new async function in `CallbackBridge.swift`:

```swift
/// Detaches a disk image using hdiutil
///
/// This is more reliable than DiskArbitration for .dmg files due to macOS security restrictions.
///
/// - Parameters:
///   - bsdName: The BSD device name (e.g., "disk4")
///   - force: Whether to force detach
/// - Returns: Result of the detach operation
nonisolated internal func detachDiskImageAsync(
  bsdName: String,
  force: Bool = false
) async -> DiskOperationResult
```

Implementation should:
- Use `Process` to run `hdiutil detach /dev/bsdName`
- Add `-force` flag if `force` is true
- Capture stdout/stderr
- Parse exit code (0 = success)
- Return `DiskOperationResult` with appropriate error handling
- Measure duration

### 3. Update Ejection Logic

Modify `ejectPhysicalDevice()` in `DiskSession.swift` (around line 300):

**Current flow:**
```swift
if options.ejectPhysicalDevice {
  // Step 1: Unmount
  let unmountResult = await unmountDiskAsync(...)

  // Step 2: Eject
  let ejectResult = await ejectDiskAsync(...)
}
```

**New flow:**
```swift
if options.ejectPhysicalDevice {
  // Check if all volumes in this group are disk images
  let allDiskImages = deviceGroup.volumes.allSatisfy { $0.info.isDiskImage }

  if allDiskImages {
    // Use hdiutil detach for disk images
    let detachResult = await detachDiskImageAsync(
      bsdName: deviceGroup.wholeDiskBSDName,
      force: options.force
    )
    return deviceGroup.volumes.map { /* map result */ }
  } else {
    // Use DiskArbitration for regular disks (existing code)
    let unmountResult = await unmountDiskAsync(...)
    let ejectResult = await ejectDiskAsync(...)
  }
}
```

### 4. Error Handling

- If `hdiutil` is not found, fall back to DiskArbitration
- If `hdiutil` fails, include stderr in error message
- Log when using `hdiutil` vs DiskArbitration (optional debug output)

### 5. Testing

Test with:
```bash
# Create a multi-partition disk image
hdiutil create -size 200m -layout GPTSPUD -fs "Case-sensitive APFS" /tmp/multipart.dmg

# Attach and partition it
DEV=$(hdiutil attach -nomount /tmp/multipart.dmg | head -1 | awk '{print $1}')
diskutil partitionDisk $DEV 2 GPT APFS Part1 50% APFS Part2 50%

# Test ejection
sudo ./org.deverman.ejectalldisks.sdPlugin/bin/eject-disks eject

# Verify both partitions are ejected successfully
```

Expected behavior:
- Both partitions should eject without "Not privileged" errors
- Debug output should show using `hdiutil detach` for disk images
- Grouping optimization should still work (2 volumes → 1 physical device)

## Files to Modify

1. **`swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/Internal/CallbackBridge.swift`**
   - Add `detachDiskImageAsync()` function

2. **`swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/DiskSession.swift`**
   - Modify `ejectPhysicalDevice()` method (around line 300)
   - Add logic to detect disk images and use `hdiutil` when appropriate

## Success Criteria

- [ ] Disk images eject successfully without "Not privileged" errors
- [ ] Regular disks continue to use DiskArbitration (no regression)
- [ ] Multi-partition disk images are handled as one group
- [ ] Error messages are clear when `hdiutil` fails
- [ ] All tests pass
- [ ] Benchmark shows successful ejection of disk images

## Notes

- `hdiutil detach` automatically unmounts all volumes, so we don't need separate unmount step
- The `/dev/` prefix is required for `hdiutil detach`
- Force flag in `hdiutil` is `-force` (with dash)
- Exit code 0 = success, non-zero = failure
- stderr contains error messages when `hdiutil` fails
