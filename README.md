# Eject All Disks - Stream Deck Plugin

A Stream Deck plugin that adds a button to safely eject all external disks on macOS with a single button press. This plugin provides visual feedback during the ejection process and allows customization of the button appearance.

## Features

- **Real-time disk count monitoring** - Shows the number of attached external disks on the button icon
- **Automatic updates** - Icon badge updates every 3 seconds when disks are mounted/unmounted
- Single button to eject all external disks
- Visual feedback for ejection status (normal, ejecting, success, error)
- Customizable button title visibility
- Safe disk ejection using macOS `diskutil`
- Animated states during ejection
- Comprehensive error handling with visual indicators

## Requirements

- macOS 12 or later
- Stream Deck 6.4 or later
- Stream Deck SDK 2.0 (beta)
- Node.js 20 or later

## Installation

1. Download the latest release from the [releases page](https://github.com/deverman/eject_all_disks_streamdeck/releases)
2. Double-click the downloaded `.streamDeckPlugin` file to install it
3. Stream Deck will prompt you to install the plugin

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
- Uses macOS's built-in `diskutil` command with validation
- Validates disk paths before ejection
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
├── org.deverman.ejectalldisks.sdPlugin/  # Plugin resources
│   ├── bin/                # Compiled JavaScript
│   ├── ui/                 # Property Inspector HTML
│   ├── imgs/               # Icons and images
│   ├── libs/               # Library files
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

To see plugin output and debug messages:

**Method 1: Stream Deck Log File**
```bash
# macOS - View live logs
tail -f ~/Library/Logs/com.elgato.StreamDeck/StreamDeck0.log
```

**Method 2: Stream Deck App**
1. Open Stream Deck application
2. Go to Preferences → Advanced
3. Click "Open Plugin Log Folder"
4. Open the latest log file

**Method 3: Console.app**
1. Open Console.app (Applications → Utilities)
2. Search for "StreamDeck" or "Eject All Disks"
3. View real-time logs

#### What to Look For in Logs

The plugin outputs these key messages:
```
Eject All Disks plugin initializing
Disk count changed to: 2
Ejecting disks...
Disks ejected: [output]
Error counting disks: [error details]
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

#### Shell Command
The plugin uses a secure shell command to safely eject disks:
```bash
IFS=$'\n'
disks=$(diskutil list external | grep -o -E '/dev/disk[0-9]+')
for disk in $disks; do
  # Validate disk path format for security
  if [[ "$disk" =~ ^/dev/disk[0-9]+$ ]]; then
    diskutil unmountDisk "$disk"
  else
    echo "Invalid disk path: $disk" >&2
  fi
done
```

This implementation includes security measures like path validation and proper error handling.

## Troubleshooting

### Common Issues

1. **Button shows error state:**
   - Ensure disks aren't currently in use by applications
   - Check for file operations in progress
   - Try ejecting through Finder first to see specific error messages

2. **Settings not saving:**
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
