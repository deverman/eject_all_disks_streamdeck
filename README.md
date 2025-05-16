# Eject All Disks - Stream Deck Plugin

A Stream Deck plugin that adds a button to safely eject all external disks on macOS with a single button press. This plugin provides visual feedback during the ejection process and allows customization of the button appearance.

## Features

- Single button to eject all external disks
- Visual feedback for ejection status (normal, ejecting, success, error)
- Customizable button title visibility
- Safe disk ejection using macOS `diskutil`
- Animated states during ejection
- Comprehensive error handling with visual indicators

## Requirements

- macOS 12 or later
- Stream Deck 6.4 or later
- Stream Deck Software

## Installation

1. Download the latest release from the [releases page](https://github.com/deverman/eject-all-disks-streamdeck/releases)
2. Double-click the downloaded `.streamDeckPlugin` file to install it
3. Stream Deck will prompt you to install the plugin

## Usage

1. Drag the "Eject All Disks" action from the "Eject All Disks" category onto your Stream Deck
2. Press the button to eject all external disks
3. The button will display the ejection status visually
4. Configure the button to show or hide the title text via Settings

### Button States

- **Default**: Standard eject icon
- **Ejecting**: Animated eject icon while process runs
- **Success**: Green checkmark with eject icon
- **Error**: Red X with eject icon

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

4. Create icons and resources:
   - SVG icons in the appropriate directories
   - Property inspector HTML
   - Update manifest.json

5. Pack the plugin:
```bash
# Create dist directory if it doesn't exist
mkdir -p dist

# Pack the plugin
streamdeck pack org.deverman.ejectalldisks.sdPlugin --output dist
```

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
1. Check the [Issues](https://github.com/deverman/eject-all-disks-streamdeck/issues) page
2. File a new issue with:
   - macOS version
   - Stream Deck software version
   - Steps to reproduce
   - Error messages if any
