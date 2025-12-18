# Changelog

All notable changes to the Eject All Disks Stream Deck plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-11-24

### Added

- **Native DiskArbitration API** - Uses macOS DiskArbitration framework (`DADiskUnmount` + `DADiskEject`) for ~6x faster disk ejection compared to `diskutil` subprocess calls
- **Privilege Setup System** - One-time sudoers configuration for passwordless disk ejection
    - Setup script at `bin/install-eject-privileges.sh`
    - Property inspector shows setup status and instructions
    - "Check Status" button to verify configuration
    - "Copy Command" button for easy terminal setup
- **Blocking Process Detection** - Shows which processes are preventing disk ejection (using `lsof`)
- **Benchmark Command** - `./eject-disks benchmark --eject` to measure ejection performance
- **SETUP.md** - Comprehensive privilege setup documentation

### Changed

- Swift CLI binary now uses DiskArbitration framework instead of spawning `diskutil` subprocesses
- Improved error messages with detailed status codes from DiskArbitration
- Updated README with new features and troubleshooting guide

### Technical Details

- Swift package `SwiftDiskArbitration` provides async/await wrappers for DiskArbitration C APIs
- Uses `kDADiskUnmountOptionWhole` to unmount all volumes on a physical disk
- Parallel ejection using Swift concurrency (`TaskGroup`)
- Proper memory management for C callback bridging using `Unmanaged`

## [0.1.0] - Initial Release

### Added

- Basic disk ejection using `diskutil eject` subprocess
- Real-time disk count monitoring with badge display
- Visual feedback for ejection status (normal, ejecting, success, error)
- Customizable button title visibility
- Property inspector for settings
- SVG-based dynamic icons
