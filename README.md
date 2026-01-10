# Eject All Disks - Stream Deck Plugin

A Stream Deck plugin that adds a button to safely eject all external disks on macOS with a single button press. This plugin provides visual feedback during the ejection process and allows customization of the button appearance.

## Features

- **Fast native disk ejection** - Uses macOS DiskArbitration framework for ~6x faster ejection than diskutil
- **Pure Swift implementation** - Native Stream Deck plugin with no Node.js or shell script dependencies
- **Real-time disk count monitoring** - Shows the number of attached external disks on the button
- **Automatic updates** - Disk count updates every 3 seconds as disks are mounted/unmounted
- Single button to eject all external disks in parallel
- Visual feedback for ejection status (normal, ejecting, success, error)
- Customizable button title visibility
- Comprehensive error handling with detailed logging

## Requirements

- macOS 13 or later
- Stream Deck 6.4 or later
- Xcode Command Line Tools (for building from source)

## Installation

### From Release

1. Download the latest release from the [releases page](https://github.com/deverman/eject_all_disks_streamdeck/releases)
2. Double-click the downloaded `.streamDeckPlugin` file to install it
3. Stream Deck will prompt you to install the plugin

### From Source

See [Development](#development) section below.

## Usage

1. Drag the "Eject All Disks" action from the "Eject All Disks" category onto your Stream Deck
2. The button will automatically display the number of external disks currently attached
3. The count updates automatically every 3 seconds as you mount/unmount disks
4. Press the button to eject all external disks
5. The button will display the ejection status visually
6. Configure the button to show or hide the title text via Settings

### Button States

| State | Description |
|-------|-------------|
| **Default** | Shows "X Disk(s)" or "Eject All Disks" if none connected |
| **Ejecting** | Shows "Ejecting..." while operation runs |
| **Success** | Shows "Ejected!" with success indicator |
| **No Disks** | Shows "No Disks" if nothing to eject |
| **Error** | Shows "Error" or "Failed" with alert indicator |

### Settings

In the Stream Deck button configuration:

- **Show Title**: Toggle to show/hide the disk count text on the button

## Development

### Prerequisites

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9 or later

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
├── org.deverman.ejectalldisks.sdPlugin/  # Plugin bundle
│   ├── bin/                         # Compiled binary
│   ├── ui/                          # Property Inspector HTML
│   ├── imgs/                        # Icons and images
│   └── manifest.json                # Plugin configuration
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
./build.sh --update-manifest
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
npx streamdeck link org.deverman.ejectalldisks.sdPlugin
```

**Option 2: Manual Symlink**

```bash
# Close Stream Deck first
ln -sf "$(pwd)/org.deverman.ejectalldisks.sdPlugin" \
  ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/
```

Then restart the Stream Deck application.

### Development Workflow

1. Make changes to Swift files in `swift-plugin/Sources/`
2. Rebuild: `cd swift-plugin && ./build.sh`
3. Restart plugin: `npx streamdeck restart org.deverman.ejectalldisks`
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

- Ensure the binary exists: `ls org.deverman.ejectalldisks.sdPlugin/bin/`
- Run `./build.sh --update-manifest` to update the manifest
- Restart Stream Deck application completely
- Check that `manifest.json` has correct paths

**Build errors:**

- Ensure Xcode Command Line Tools are installed: `xcode-select --install`
- Check Swift version: `swift --version` (requires 5.9+)
- Clean build: `cd swift-plugin && swift package clean && ./build.sh`

**Disk count not updating:**

- Check logs for errors: `log stream --predicate 'subsystem == "org.deverman.ejectalldisks"'`
- Verify you have external disks mounted (not internal)
- Make sure the action is visible on your Stream Deck

### Packaging for Distribution

```bash
cd swift-plugin
./build.sh --update-manifest

# Package the plugin
mkdir -p dist
cd ..
zip -r dist/org.deverman.ejectalldisks.streamDeckPlugin \
  org.deverman.ejectalldisks.sdPlugin \
  -x "*.DS_Store" -x "*/logs/*" -x "*.log"
```

## Architecture

### Swift Plugin Structure

The plugin uses the [StreamDeckPlugin](https://github.com/emorydunn/StreamDeckPlugin) Swift library:

- **EjectAllDisksPlugin** - Main plugin class that handles initialization and disk monitoring
- **EjectAction** - KeyAction that responds to button presses and manages the eject operation
- **SwiftDiskArbitration** - Local library providing async/await wrapper around macOS DiskArbitration framework

### Disk Ejection

The plugin uses the macOS DiskArbitration framework directly:

1. Enumerates all mounted volumes using `DADiskCreateFromVolumePath`
2. Filters to external, ejectable volumes only
3. Unmounts each volume using `DADiskUnmount`
4. Ejects the physical device using `DADiskEject`
5. Runs all operations in parallel using Swift concurrency

This approach is ~6x faster than calling `diskutil eject` as a subprocess.

## Security

This plugin:

- Only ejects external disks (not internal drives)
- Uses macOS's native DiskArbitration framework for safe unmount and eject
- Validates disk paths before ejection
- Runs entirely in user space with no elevated privileges required
- Cannot access any other system resources

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
