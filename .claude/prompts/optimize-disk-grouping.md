# COMPLETE: finished on branch and merged to main claude/optimize-disk-grouping-01JumRhy5R8EhetiRKF1A8hG
# Optimization: Disk Grouping by Physical Device

## Goal
Optimize disk ejection by grouping volumes by their physical device (BSD whole disk) before ejection, reducing redundant operations.

## Current Behavior
- Each volume is processed individually
- `unmountAndEjectAsync` is called for each volume separately
- For a disk with 3 partitions, we may be doing redundant work

## Proposed Change
1. In `DiskSession.swift`, add a method to group volumes by their whole disk BSD name
2. Modify `ejectAll()` to:
   - Group volumes by physical device first
   - For each physical device, unmount all its volumes with `kDADiskUnmountOptionWhole`
   - Then eject the physical device once
   - Process different physical devices in parallel

## Files to Modify
- `swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/DiskSession.swift`
- `swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/Internal/CallbackBridge.swift`

## Key Code Locations
- `DiskSession.ejectAll()` method
- `unmountAndEjectAsync()` function in CallbackBridge.swift

## Expected Improvement
- Reduce redundant unmount calls for multi-partition disks
- Faster ejection for disks with multiple volumes

## Testing
1. Mount a disk with multiple partitions
2. Run `./eject-disks benchmark --eject`
3. Compare timing before and after optimization
