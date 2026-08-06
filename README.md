# SafeEject: One-Push Disk Manager

SafeEject is a Stream Deck plugin that adds a button to safely eject all external disks on macOS with a single button press. This plugin provides visual feedback during the ejection process and allows customization of the button appearance.

## Features

- **Fast native disk ejection** - Uses macOS DiskArbitration framework (typically ~6–10x faster than `diskutil`)
- **Pure Swift implementation** - Native Stream Deck plugin with no Node.js or shell script dependencies
- **Truthful real-time disk state** - Fresh enumeration on first paint, event-driven updates, and a low-frequency drift check while a key is visible
- Single button to eject all external disks in parallel
- Progressive visual feedback for normal, slow, attention, confirmed success, and typed error states
- Customizable button title visibility
- Comprehensive error handling with detailed logging

## Requirements

- macOS 26 or later (SafeEject 4.0.0 no longer supports macOS 13–15)
- Stream Deck 6.9 or later
- **Full Disk Access permission** (see [Permissions](#permissions) below)
- Xcode Command Line Tools (for building from source)

## Installation

### From Release

1. Download the latest release from the [releases page](https://github.com/deverman/eject_all_disks_streamdeck/releases)
2. Double-click the downloaded `.streamDeckPlugin` file to install it
3. Stream Deck will prompt you to install the plugin

### From Source

See [Development](#development) section below.

## Permissions

This plugin requires **Full Disk Access** permission to eject disks. Without this permission, disk ejection operations will fail silently or return permission errors.

### Granting Full Disk Access

1. Open **System Settings** (or System Preferences on older macOS)
2. Navigate to **Privacy & Security** > **Full Disk Access**
3. Click the **+** button to add an application
4. Navigate to the Stream Deck application:
   - `/Applications/Elgato Stream Deck.app`
5. Enable the toggle next to Stream Deck
6. Restart the Stream Deck application

Alternatively, if you're running the plugin binary directly for development:

1. Add the plugin binary to Full Disk Access:
   - `~/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/org.deverman.ejectalldisks`

### Why Full Disk Access?

The macOS DiskArbitration framework requires elevated permissions to unmount and eject volumes. This is a security feature to prevent malicious apps from ejecting disks without user consent. By granting Full Disk Access to Stream Deck, you're authorizing it to perform disk operations on your behalf.

## Usage

1. Drag the "SafeEject All" action from the "SafeEject: One-Push Disk Manager" category onto your Stream Deck
2. The button will automatically display the number of external disks currently attached
3. The count reacts to macOS mount/unmount/rename/wake events; a 30-second fallback check catches rare missed notifications while a key is visible
4. Press the button to eject all external disks
5. The button will display the ejection status visually
6. Configure the button to show or hide the title text via Settings

### Button States

| State | Description |
|-------|-------------|
| **Idle (disks connected)** | Shows "X Disk(s)" count |
| **Idle (no disks)** | Shows "No Disks" |
| **Checking** | Shows "Checking…" until a fresh inventory is known |
| **Ejecting** | Shows "Ejecting…", then "Working…" at 3 seconds and "Check Disk" at 15 seconds if macOS is still working |
| **Success** | Shows "Ejected!" only after macOS confirms physical eject |
| **Error** | Shows error details: "In Use", "1 of 3 Failed", "Grant Access", etc. |
| **Timeout/unconfirmed** | Shows "Check Disk"; never claims the disk is safe to remove |

### Settings

In the Stream Deck button configuration:

- **Show Title**: Toggle to show/hide the disk count text on the button

## Development

### Prerequisites

- macOS 26 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 6.3.3 or later

### Project Structure

```
eject_all_disks_streamdeck/
├── swift-plugin/                    # Swift Stream Deck plugin
│   ├── Sources/EjectAllDisksPlugin/ # Plugin source code
│   │   ├── Actions/                 # Stream Deck actions
│   │   │   └── EjectAction.swift    # Main eject action
│   │   └── EjectAllDisksPlugin.swift # Plugin entry point
│   ├── Tests/                       # Swift Testing tests
│   ├── Package.swift                # Swift package manifest
│   └── build.sh                     # Build script
├── swift/                           # SwiftDiskArbitration library
│   └── Packages/SwiftDiskArbitration/
├── org.deverman.ejectalldisks.sdPlugin/  # Plugin bundle assets
│   ├── org.deverman.ejectalldisks   # Compiled binary (in installed bundle after export)
│   ├── ui/                          # Property Inspector HTML
│   ├── imgs/                        # Icons and images
│   └── manifest.json                # Generated during export (not stored in repo)
└── README.md                        # This file
```

### Building the Plugin

1. Clone the repository:

```bash
git clone https://github.com/deverman/eject_all_disks_streamdeck.git
cd eject_all_disks_streamdeck
```

2. Build the Swift plugin:

```bash
cd swift-plugin
./build.sh --install
```

This compiles the Swift plugin and copies the binary to the plugin bundle.

### Running Tests

```bash
cd swift-plugin
swift test
```

### Installing for Development

**Option 1: Using Stream Deck CLI (Recommended)**

```bash
streamdeck link org.deverman.ejectalldisks.sdPlugin
```

Note: Install the Stream Deck CLI with `npm install -g @elgato/cli` if not already installed.

**Option 2: Manual Symlink**

```bash
# Close Stream Deck first
ln -sf "$(pwd)/org.deverman.ejectalldisks.sdPlugin" \
  ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/
```

Then restart the Stream Deck application.

### Development Workflow

1. Make changes to Swift files in `swift-plugin/Sources/`
2. Build and install: `cd swift-plugin && ./build.sh --install`
3. Restart plugin: `streamdeck restart org.deverman.ejectalldisks`
4. Or restart Stream Deck application completely

### Viewing Logs

**Plugin logs via system log:**

```bash
log stream --predicate 'subsystem == "org.deverman.ejectalldisks"' --level debug
```

**Stream Deck application logs:**

```bash
tail -f ~/Library/Logs/com.elgato.StreamDeck/StreamDeck0.log
```

### Common Development Issues

**Plugin doesn't appear in Stream Deck:**

- Ensure the binary exists in the installed bundle:
  `~/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/org.deverman.ejectalldisks`
- Run `./build.sh --install` to build and install the plugin
- Restart Stream Deck application completely
- Check that the generated `manifest.json` exists in the installed bundle:
  `~/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/manifest.json`

**Build errors:**

- Ensure Xcode Command Line Tools are installed: `xcode-select --install`
- Check Swift version: `swift --version` (requires 6.3.3+)
- Clean build: `cd swift-plugin && swift package clean && ./build.sh`

**Disk count not updating:**

- Check logs for errors: `log stream --predicate 'subsystem == "org.deverman.ejectalldisks"'`
- Verify you have external disks mounted (not internal)
- Make sure the action is visible on your Stream Deck

### Packaging for Distribution

```bash
# Build the plugin first
cd swift-plugin
./build.sh --install

# Package using Stream Deck CLI (recommended)
# Note: manifest.json is generated during export into the installed bundle.
PLUGIN_DIR="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin"
streamdeck pack "$PLUGIN_DIR"

# Or manually create a .streamDeckPlugin file
# zip -r org.deverman.ejectalldisks.streamDeckPlugin \
#   "$PLUGIN_DIR" \
#   -x "*.DS_Store" -x "*/logs/*" -x "*.log"
```

The `streamdeck pack` command creates a properly formatted `.streamDeckPlugin` file ready for distribution.

## Architecture

### Swift Plugin Structure

The plugin uses the [StreamDeckPlugin](https://github.com/deverman/StreamDeckPlugin) Swift library:

- **EjectAllDisksPlugin** - Main plugin metadata and host lifecycle edge
- **EjectAction** - Thin Stream Deck callback edge that submits immutable event snapshots
- **EjectCoordinator / EjectReducer** - Ordered actor runtime plus pure enum-driven state machine
- **DiskCountMonitor** - Subscriber-only AppKit notification and fallback-timer owner
- **StreamDeckRenderer** - Token- and revision-checked transport actor
- **SwiftDiskArbitration** - Local library providing async/await wrapper around macOS DiskArbitration framework

### Disk Ejection

The plugin uses the macOS DiskArbitration framework directly:

1. Enumerates all mounted volumes using `DADiskCreateFromVolumePath`
2. Filters to external, ejectable volumes only
3. Resolves synthesized storage layers such as APFS through the public I/O
   Registry service ancestry into an inner-to-outer whole-media stack
4. Groups branches by physical device and requests whole-device unmount for
   each distinct innermost mounted branch using `DADiskUnmount`
5. Ejects synthesized whole-media layers before the physical device using
   `DADiskEject`; only the final physical callback can confirm success
6. Runs independent physical-device operations in parallel using Swift concurrency

`Ejected!` is reachable only from a successful physical-eject callback. A busy
or permission dissenter is shown immediately. Unmount has a 25-second absolute
deadline and the entire per-device operation has one monotonic 30-second hard
watchdog; these are exceptional ceilings, not normal waits.

Apple defines a whole `IOMedia` as either a physical disk or a virtual replica,
so `DADiskCopyWholeDisk` alone is not sufficient for APFS. SafeEject retains
the complete whole-media ancestry and ejects it inner-to-outer; for example,
virtual `disk7` before physical `disk6`. It fails closed if ancestry is
unavailable or has multiple parents. Pressing the key when no disks are mounted
is a neutral no-op; green is reserved for confirmed physical eject.

This approach is typically ~6–10x faster than calling `diskutil eject` as a subprocess (machine and disk dependent).

## Security

This plugin is designed with security as a priority:

### System Volume Protection

- Uses **macOS system APIs** (not volume names) to detect protected volumes
- Checks `.volumeIsRootFileSystemKey` to identify the boot drive regardless of its name
- Checks `.volumeIsBrowsableKey` to skip system-only volumes (Recovery, Preboot, etc.)
- Additional DiskArbitration property checks for edge cases
- **Never relies on hardcoded volume names** - safe even if you renamed "Macintosh HD"

### Privacy

- **Does not log volume names** - avoids exposing sensitive information like "ConfidentialProject"
- Only logs BSD device names (e.g., "disk2s1") when debug logging is enabled
- Logs are written using OSLog with appropriate privacy levels
- Terminal success summaries are retained at notice level; failures, timeouts,
  and cancellations are retained at error level for later support diagnosis

### Permissions

- Uses macOS's native DiskArbitration framework for safe unmount and eject
- Requires Full Disk Access permission (user must explicitly grant)
- Runs entirely in user space - no root/sudo required
- Cannot access files on disks, only mount/unmount operations

## Troubleshooting

### Common Issues

1. **Button shows error state:**
   - Check logs for which process is blocking ejection
   - Common blockers: Spotlight (`mds`), backup apps, file sync apps
   - Try pressing the button again - temporary locks often release quickly

2. **Disk won't eject but Finder can eject it:**
   - Finder sends a "please close files" notification to apps before ejecting
   - The native API doesn't send this notification
   - Pause or quit the blocking application, then try again

3. **Disk count shows 0 but disks are connected:**
   - Only external, ejectable volumes are counted
   - Network drives and internal volumes are excluded
   - Check that disks appear in Finder sidebar

4. **Plugin not loading:**
   - Verify binary exists and is executable
   - Check Stream Deck logs for error messages
   - Try reinstalling the plugin

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues:

1. Check the [Issues](https://github.com/deverman/eject_all_disks_streamdeck/issues) page
2. File a new issue with:
   - macOS version
   - Stream Deck software version
   - Steps to reproduce
   - Log output if available

## Credits

Created by [Brent Deverman](https://deverman.org)
