# SwiftDiskArbitration

A modern Swift wrapper for macOS DiskArbitration framework with async/await support.

## Features

- **Fast** disk ejection compared to `diskutil` subprocess (no process spawning)
- **Swift concurrency** friendly APIs (actors + async/await)
- **Async/await** APIs for all disk operations
- Absolute monotonic 25-second unmount and 30-second overall watchdogs
- Leak-free opaque-token callback bridge with exactly-once completion
- Per-physical-device progress and structured stage/status failures
- **Actor-based** session management for thread safety
- Direct `DADiskUnmount` calls (no subprocess spawning)

## Requirements

- macOS 26+
- Swift 6.3.3+
- Xcode 26+ or an equivalent Swift 6.3.3 toolchain

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(path: "Packages/SwiftDiskArbitration"),
    // Or from a git repository:
    // .package(url: "https://github.com/yourname/SwiftDiskArbitration.git", from: "1.0.0"),
]
```

## Quick Start

```swift
import SwiftDiskArbitration

// Eject all external volumes
if let session = DiskSession.shared {
    let result = await session.ejectAllExternal()
    print("Ejected \(result.successCount)/\(result.totalCount) volumes in \(result.totalDuration)s")
}

// Or enumerate and eject selectively
let session = try DiskSession()
let volumes = await session.enumerateEjectableVolumes()

for volume in volumes {
    print("Found: \(volume.info.name)")

    let result = await session.unmount(volume)
    if result.success {
        print("  Ejected in \(result.duration)s")
    } else {
        print("  Failed: \(result.error!)")
    }
}
```

## API Reference

### DiskSession

The main entry point for disk operations. Uses actor isolation for thread safety.

```swift
// Shared singleton
let session = DiskSession.shared // Optional: session creation can fail gracefully.

// Or create your own
let session = try DiskSession()

// Enumerate volumes
let volumes = await session?.enumerateEjectableVolumes() ?? []
let count = await session?.ejectableVolumeCount() ?? 0

// Eject single volume
let result = await session.unmount(volume)
let result = await session.unmount(path: "/Volumes/MyDrive")

// Eject all volumes
let batchResult = await session.ejectAll(volumes)
let batchResult = await session.ejectAllExternal()
```

### EjectOptions

Control unmount/eject behavior:

```swift
// Default: unmount and eject physical device
await session.unmount(volume, options: .default)

// Unmount only (don't physically eject)
await session.unmount(volume, options: .unmountOnly)

// Force eject (may cause data loss if files are open)
await session.unmount(volume, options: .forceEject)

// Custom options
let options = EjectOptions(force: true, ejectPhysicalDevice: false)
await session.unmount(volume, options: options)
```

### Volume

Represents a mounted volume with cached DADisk reference:

```swift
let volume: Volume

// Access volume information
volume.info.name        // "My USB Drive"
volume.info.path        // "/Volumes/My USB Drive"
volume.info.bsdName     // "disk2s1"
volume.info.isEjectable // true
volume.info.isRemovable // true
volume.info.isInternal  // false
volume.info.isDiskImage // false
```

### DiskError

Swift-native error types for disk operations:

```swift
do {
    // ... disk operation
} catch let error as DiskError {
    switch error {
    case .busy(let message):
        print("Disk busy: \(message ?? "files in use")")
    case .notPermitted(let message):
        print("Not permitted: \(message ?? "check permissions")")
    default:
        print("Error: \(error)")
    }

    if error.isDiskBusy {
        print("Try closing applications using the disk")
    }
}
```

## Performance Comparison

These numbers are illustrative and vary by machine, connected devices, and filesystem state (Spotlight, open files, etc.).

| Method                        | 1 disk  | 3 disks  | 5 disks |
| ----------------------------- | ------- | -------- | ------- |
| `diskutil eject` (subprocess) | ~50ms   | ~60ms    | ~70ms   |
| `DADiskUnmount` (native)      | ~5ms    | ~7ms     | ~10ms   |
| **Speedup**                   | **10x** | **8.5x** | **7x**  |

The native API avoids the overhead of:

- Process forking (~5ms)
- exec() system call (~10ms)
- diskutil initialization (~15ms)
- Process cleanup (~2ms)

## Architecture

```
SwiftDiskArbitration/
├── DiskSession.swift      # Actor-based session management
├── Volume.swift           # Volume model with cached DADisk
├── DiskError.swift        # Swift error types
├── SwiftDiskArbitration.swift  # Public API re-exports
└── Internal/
    ├── CallbackBridge.swift              # Absolute-deadline orchestration
    ├── DiskOperationRegistry.swift       # Mutex + opaque token completion race
    ├── DiskArbitrationUnsafeAdapter.swift # Audited C/pointer boundary
    └── DiskOperationTiming.swift         # Clock-generic deadline policy
```

### Memory Management

The package never passes a retained Swift object to DiskArbitration. It encodes
a nonzero integer as an opaque callback cookie and stores the continuation in a
`Synchronization.Mutex` registry. Callback, watchdog, and cancellation atomically
remove the same entry; only the winner resumes it, outside the mutex. Missing,
late, duplicate, unknown, and nil callback contexts therefore cannot leak or
access freed Swift memory. `DiskSession` uses an isolated deinitializer to
unschedule its `DASession` without `nonisolated(unsafe)` state.

### Thread Safety

- `DiskSession` is an actor - all state access is serialized
- The callback registry uses `Synchronization.Mutex` for its synchronous C boundary
- All elapsed time and deadlines use `ContinuousClock`
- Child tasks operate independently per physical device and publish typed progress
- The package builds in Swift 6 mode with strict memory safety, warnings-as-errors,
  explicit public `Sendable` declarations, and debug actor race checks

## License

MIT License - see LICENSE file for details.

## Credits

Based on research from:

- [Apple DiskArbitration Documentation](https://developer.apple.com/documentation/diskarbitration)
- [Ejectify by Niels Mouthaan](https://github.com/nielsmouthaan/ejectify-macos)
- Swift Forums discussions on C callback bridging
