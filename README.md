# Eject All Disks - Stream Deck Plugin

A Stream Deck plugin that adds a button to safely eject all external disks on macOS with a single button press. This plugin provides visual feedback during the ejection process and allows customization of the button appearance.

## Features

- **Fast native disk ejection** - Uses macOS DiskArbitration framework for ~6x faster ejection than diskutil
- **Real-time disk count monitoring** - Shows the number of attached external disks on the button icon
- **Automatic updates** - Icon badge updates every 3 seconds when disks are mounted/unmounted
- Single button to eject all external disks in parallel
- Visual feedback for ejection status (normal, ejecting, success, error)
- Customizable button title visibility
- Animated states during ejection
- Comprehensive error handling with blocking process detection

## Requirements

- macOS 12 or later
- Stream Deck 6.4 or later
- Stream Deck SDK 2.0 (beta)
- Node.js 20 or later

## Installation

1. Download the latest release from the [releases page](https://github.com/deverman/eject_all_disks_streamdeck/releases)
2. Double-click the downloaded `.streamDeckPlugin` file to install it
3. Stream Deck will prompt you to install the plugin

## Initial Setup (One-Time)

For the fastest and most reliable disk ejection, run the privilege setup script once:

1. Open the Stream Deck action's property inspector (click on the Eject All Disks button)
2. In the "Privilege Setup" section, check the status
3. If not configured, copy the setup command and run it in Terminal
4. Enter your admin password when prompted

This configures your system to allow passwordless disk ejection using macOS's sudoers mechanism. Without this setup, the plugin will still work but may show "Not privileged" errors for some volumes.

For detailed instructions, see [SETUP.md](org.deverman.ejectalldisks.sdPlugin/SETUP.md).

## Usage

1. Drag the "Eject All Disks" action from the "Eject All Disks" category onto your Stream Deck
2. The button will automatically display the number of external disks currently attached (shown in a red badge in the top-right corner)
3. The count updates automatically every 3 seconds as you mount/unmount disks
4. Press the button to eject all external disks
5. The button will display the ejection status visually
6. Configure the button to show or hide the title text via Settings

### Button States

- **Default**: Standard eject icon with disk count badge (if disks are present)
- **Ejecting**: Animated eject icon while process runs
- **Success**: Green checkmark with eject icon
- **Error**: Red X with eject icon

The disk count badge appears as a red circle in the top-right corner of the icon, showing the number of external disks currently mounted.

### Settings

In the Stream Deck button configuration:

- **Show Title**: Toggle to show/hide the "Eject All Disks" text on the button

## Security

This plugin:

- Only ejects external disks (not internal drives)
- Uses macOS's native DiskArbitration framework for safe unmount and eject
- Validates disk paths before ejection
- Optional sudoers setup grants privileges only for the specific eject binary
- Cannot access any other system resources

## Development

### Prerequisites

- Node.js 20 or later
- TypeScript
- Stream Deck SDK and CLI

### Project Structure

```
eject_all_disks_streamdeck/
├── src/                    # TypeScript source files
│   ├── actions/            # Action implementations
│   └── plugin.ts           # Plugin entry point
├── swift/                  # Swift CLI binary source
│   ├── Sources/            # Swift source files
│   └── Package.swift       # Swift package configuration
├── org.deverman.ejectalldisks.sdPlugin/  # Plugin resources
│   ├── bin/                # Compiled JS + Swift binary
│   ├── ui/                 # Property Inspector HTML
│   ├── imgs/               # Icons and images
│   ├── logs/               # Plugin log files (auto-created)
│   └── manifest.json       # Plugin configuration
├── dist/                   # Packaged plugin (.streamDeckPlugin)
└── README.md               # This file
```

### Building the Plugin

1. Clone the repository:

```bash
git clone https://github.com/brentdeverman/eject-all-disks-streamdeck.git
cd eject-all-disks-streamdeck
```

2. Install dependencies:

```bash
npm install
```

3. Build the TypeScript code:

```bash
npm run build
```

This compiles the TypeScript source files from `src/` into JavaScript in `org.deverman.ejectalldisks.sdPlugin/bin/`.

### Testing and Development

#### Quick Start - Testing in Stream Deck

**Option 1: Link for Development (Recommended)**

```bash
# 1. Build the plugin first
npm run build

# 2. Link the plugin to Stream Deck
npx streamdeck link

# 3. Restart Stream Deck application
# The plugin should now appear in Stream Deck
```

The `link` command creates a symlink so Stream Deck loads your plugin directly from the development directory.

**Option 2: Install the Package**

```bash
# Build and package
npm run build
cd org.deverman.ejectalldisks.sdPlugin
zip -r ../dist/org.deverman.ejectalldisks.streamDeckPlugin . -x "*.DS_Store"
cd ..

# Double-click the .streamDeckPlugin file to install
open dist/org.deverman.ejectalldisks.streamDeckPlugin
```

#### Live Development with Watch Mode

For active development with automatic reloading:

```bash
npm run watch
```

This command:

- ✅ Watches `src/` directory for TypeScript changes
- ✅ Automatically rebuilds on file changes
- ✅ Restarts the plugin in Stream Deck automatically
- ✅ Updates when `manifest.json` changes

**While watch mode is running:**

1. Edit files in `src/`
2. Save your changes
3. Plugin automatically rebuilds and restarts
4. Changes appear in Stream Deck within seconds

**To stop watch mode:** Press `Ctrl + C`

#### Viewing Plugin Logs

Plugin logs are stored in the plugin's own directory with automatic rotation (10 files max, 10 MiB each).

**Log Location:**

```bash
~/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/logs/
```

**View the latest log:**

```bash
cat ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/logs/org.deverman.ejectalldisks.0.log
```

**Follow logs in real-time:**

```bash
tail -f ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/logs/org.deverman.ejectalldisks.0.log
```

**View recent entries:**

```bash
tail -200 ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/logs/org.deverman.ejectalldisks.0.log
```

Log files are numbered 0-9, with 0 being the most recent. A new log file is created when the plugin starts or when the current file exceeds 10 MiB.

#### What to Look For in Logs

The plugin outputs these key messages:

```
# Startup
Eject All Disks plugin starting...
Found Swift binary at: /path/to/eject-disks

# Disk monitoring
Disk count updated to: 2 for action xxx (forced: false)

# Ejection process
Ejecting disks...
Swift eject completed: 2/2 ejected, 0 failed, took 5.23s
  [OK] DiskName ejected in 5.20s
SHOWING SUCCESS ICON - All disks ejected successfully

# Errors
  [FAIL] DiskName: Unmount of disk16 failed...
Failed to eject "DiskName": error message
  Blocking processes: AppName (PID: 1234, User: username)
SHOWING ERROR ICON - Error ejecting disks: ...
```

#### Testing the Disk Count Feature

1. **Add the button to Stream Deck:**
    - Drag "Eject All Disks" from the actions panel to a key

2. **Mount external disks:**
    - Connect a USB drive or mount a disk image
    - Wait up to 3 seconds for the badge to appear

3. **Watch the counter update:**
    - Mount more disks → badge shows increasing count
    - Eject disks via Finder → badge decreases
    - All disks ejected → badge disappears

4. **Test ejection:**
    - Press the Stream Deck button
    - Icon shows animated "Ejecting..." state
    - Success: Green checkmark appears
    - Error: Red X appears with alert

5. **Check logs for errors:**
    ```bash
    tail -f ~/Library/Logs/com.elgato.StreamDeck/StreamDeck0.log | grep -i "eject"
    ```

#### Development Tips

1. **Enable Debug Mode:**
   The plugin has debug logging enabled in `manifest.json`:

    ```json
    "Nodejs": {
      "Version": "20",
      "Debug": "enabled"
    }
    ```

2. **Quick Restart:**

    ```bash
    npx streamdeck restart org.deverman.ejectalldisks
    ```

3. **Force Reload Stream Deck:**
   If changes aren't appearing, restart Stream Deck:
    - Quit Stream Deck completely
    - Reopen Stream Deck
    - Plugin loads with fresh code

4. **Validate Plugin Structure:**

    ```bash
    npx streamdeck validate org.deverman.ejectalldisks.sdPlugin
    ```

5. **Manual Disk Count Test:**
   Test the disk counting command directly:
    ```bash
    diskutil list external | grep -o -E '/dev/disk[0-9]+' | sort -u
    ```
    The output should match what appears on your Stream Deck button.

#### Common Development Issues

**Plugin doesn't appear in Stream Deck:**

- Run `npx streamdeck link` again
- Restart Stream Deck application completely
- Check that `manifest.json` has correct UUID and paths
- Verify `bin/plugin.js` exists after building

**Changes not reflecting:**

- Make sure you ran `npm run build`
- If using watch mode, check that it's still running
- Try `npx streamdeck restart org.deverman.ejectalldisks`
- Quit and reopen Stream Deck

**Disk count not updating:**

- Check logs for "Error counting disks" messages
- Verify you have external disks mounted (not internal)
- Test the diskutil command manually
- Make sure the action is visible on your Stream Deck (monitoring stops when hidden)

**Build errors:**

- Delete `node_modules` and `package-lock.json`
- Run `npm install` again
- Make sure you're using Node.js 20 or later: `node --version`

### Packaging for Distribution

To create a `.streamDeckPlugin` file for distribution:

```bash
# Method 1: Using StreamDeck CLI (if available)
npx streamdeck pack org.deverman.ejectalldisks.sdPlugin --output dist

# Method 2: Manual packaging
mkdir -p dist
cd org.deverman.ejectalldisks.sdPlugin
zip -r ../dist/org.deverman.ejectalldisks.streamDeckPlugin . -x "*.DS_Store"
cd ..
```

The packaged file will be in `dist/org.deverman.ejectalldisks.streamDeckPlugin`.

### Releasing New Versions

This project uses GitHub Actions to automate the release process. When you create a new release on GitHub, the workflow automatically builds and packages the plugin, then attaches it to the release.

#### Step-by-Step Release Process

**1. Update the version number:**

```bash
npm run version:bump 2.0.0
```

This script updates `manifest.json` with the new version (converted to 4-part format: `2.0.0.0`).

**2. Commit the version change:**

```bash
git add org.deverman.ejectalldisks.sdPlugin/manifest.json
git commit -m "Bump version to 2.0.0"
```

**3. Create and push a git tag:**

```bash
git tag -a v2.0.0 -m "Release v2.0.0"
git push && git push origin v2.0.0
```

**4. Create the GitHub release:**

Option A - Using GitHub web interface:
1. Go to https://github.com/deverman/eject_all_disks_streamdeck/releases/new?tag=v2.0.0
2. Fill in the release title and notes
3. Click "Publish release"

Option B - Using GitHub CLI:
```bash
gh release create v2.0.0 \
  --title "v2.0.0" \
  --notes "Release notes here"
```

**5. Wait for automation:**

GitHub Actions will automatically:
- Build the TypeScript code
- Package the plugin
- Upload `org.deverman.ejectalldisks.streamDeckPlugin` to the release

Users can then download the plugin directly from the releases page!

#### Version Numbering

Follow [Semantic Versioning](https://semver.org/):
- **MAJOR** (x.0.0): Breaking changes
- **MINOR** (1.x.0): New features (backwards compatible)
- **PATCH** (1.0.x): Bug fixes

Note: Stream Deck uses 4-part versioning in `manifest.json` (e.g., `2.0.0.0`), but Git tags and releases use 3-part versioning (e.g., `v2.0.0`).

### Implementation Details

#### SVG Icons

The plugin uses SVG icons for dynamic rendering with different states:

- Normal state: Orange eject icon
- Ejecting state: Animated yellow eject icon
- Success state: Green eject icon with checkmark
- Error state: Red eject icon with X mark

Each icon includes a semi-transparent background for better text contrast.

#### Settings Implementation

Settings are implemented using:

- TypeScript interface for type safety
- Default values to handle initialization
- Property Inspector for UI controls
- WebSocket communication between UI and plugin

#### Disk Ejection

The plugin uses a Swift CLI binary for fast parallel disk ejection:

**Primary method (Swift binary with DiskArbitration):**
- Uses macOS DiskArbitration framework (`DADiskUnmount` + `DADiskEject`)
- ~6x faster than `diskutil eject` subprocess calls
- Unmounts all volumes on a physical disk, then ejects the device
- Runs ejections in parallel using Swift concurrency
- Reports blocking processes when ejection fails
- Located at `bin/eject-disks` in the plugin directory

**Fallback method (Shell script):**
If the Swift binary is unavailable, the plugin falls back to a shell script that runs `diskutil eject` for each volume in parallel.

**Diagnostic commands:**
```bash
# List ejectable volumes
./eject-disks list

# Show what processes are blocking each volume
./eject-disks diagnose

# Eject all volumes with verbose output
./eject-disks eject --verbose

# Benchmark native vs diskutil speed
./eject-disks benchmark --eject
```

## Troubleshooting

### Common Issues

1. **"Not privileged" error:**
    - Run the privilege setup script (see [Initial Setup](#initial-setup-one-time))
    - Check the property inspector to verify setup status
    - The setup is required for the native DiskArbitration APIs to work

2. **Button shows error state:**
    - Check the plugin logs for which process is blocking ejection
    - Common blockers: Spotlight (`mds`), backup apps (Time Machine), file sync apps (Dropbox)
    - Run `./eject-disks diagnose` to see blocking processes
    - Try pressing the button again - temporary locks often release quickly

3. **Disk won't eject but Finder can eject it:**
    - Finder sends a "please close files" notification to apps before ejecting
    - The native API doesn't send this notification
    - Pause or quit the blocking application, then try again

4. **Settings not saving:**
    - Restart Stream Deck software
    - Check permissions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues:

1. Check the [Issues]((https://github.com/deverman/eject_all_disks_streamdeck/issues) page
2. File a new issue with:
    - macOS version
    - Stream Deck software version
    - Steps to reproduce
    - Error messages if any

## Credits

Vibe coded by [Brent Deverman](https://deverman.org) using [Zed](https://zed.dev)
