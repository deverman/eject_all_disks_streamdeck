# SwiftDiskArbitration

A modern Swift wrapper for macOS DiskArbitration framework with async/await support.

## Features

- **Fast** disk ejection compared to `diskutil` subprocess (no process spawning)
- **Swift concurrency** friendly APIs (actors + async/await)
- **Async/await** APIs for all disk operations
- Timeout-protected unmount/eject operations (prevents hangs)
- **Actor-based** session management for thread safety
- Direct `DADiskUnmount` calls (no subprocess spawning)

## Requirements

- macOS 13.0+
- Swift 6.2.1+
- Xcode 15+

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
let result = await DiskSession.shared.ejectAllExternal()
print("Ejected \(result.successCount)/\(result.totalCount) volumes in \(result.totalDuration)s")

// Or enumerate and eject selectively
let session = try DiskSession()
let volumes = session.enumerateEjectableVolumes()

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
let session = DiskSession.shared

// Or create your own
let session = try DiskSession()

// Enumerate volumes
let volumes = session.enumerateEjectableVolumes()
let count = session.ejectableVolumeCount()

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
    └── CallbackBridge.swift    # C callback to async bridge
```

### Memory Management

The package carefully manages memory for DiskArbitration callbacks:

1. **Continuation storage**: Uses `Unmanaged.passRetained()` to prevent deallocation before callback
2. **Balanced release**: Callback uses `takeRetainedValue()` to release
3. **Exactly-once resume**: Each continuation resumes exactly once
4. **Session lifecycle**: DASession unscheduled in deinit

### Thread Safety

- `DiskSession` is an actor - all state access is serialized
- Volume enumeration is `nonisolated` (read-only, thread-safe)
- C callbacks spawn Tasks to re-enter actor isolation
- `@unchecked Sendable` used only where safety is verified

## License

MIT License - see LICENSE file for details.

## Credits

Based on research from:

- [Apple DiskArbitration Documentation](https://developer.apple.com/documentation/diskarbitration)
- [Ejectify by Niels Mouthaan](https://github.com/nielsmouthaan/ejectify-macos)
- Swift Forums discussions on C callback bridging
