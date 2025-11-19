# Testing Guide for Eject All Disks Plugin

## Build Verification ✅

The plugin has been successfully built and packaged with the following features:

### ✅ Verified Components

1. **SDK Upgrade**: Upgraded to `@elgato/streamdeck` v2.0.0-beta.2
2. **Disk Count Monitoring**: Added real-time disk counting with 3-second polling
3. **Visual Badge**: Red circle badge in top-right corner showing disk count
4. **Compiled Output**: `bin/plugin.js` (267KB minified) contains all new functionality
5. **Package**: `dist/org.deverman.ejectalldisks.streamDeckPlugin` (443KB) ready for installation

### ✅ Code Features Verified in Compiled Output

- ✅ `getDiskCount()` function - counts external disks
- ✅ `updateDiskCount()` function - updates display when count changes
- ✅ `startMonitoring()` function - starts 3-second polling interval
- ✅ Badge SVG with red circle at coordinates (110, 34)
- ✅ Disk counting command: `diskutil list external | grep -o -E '/dev/disk[0-9]+' | sort -u`
- ✅ Proper cleanup on `onWillDisappear` for both timeouts and monitoring interval
- ✅ Fixed timeout cleanup bug (removed duplicate timeout additions)

## Installation on macOS

### Method 1: Double-Click Installation
1. Copy `dist/org.deverman.ejectalldisks.streamDeckPlugin` to your Mac
2. Double-click the file
3. Stream Deck will prompt you to install the plugin
4. Approve the installation

### Method 2: Development Installation
1. Clone the repository on your Mac
2. Run `npm install`
3. Run `npm run build`
4. Run `npx streamdeck link .`
5. The plugin will be linked to Stream Deck for development

## Testing the Disk Count Feature

### Test 1: Initial Display
1. Drag the "Eject All Disks" action onto your Stream Deck
2. **Expected**: Button shows eject icon WITHOUT a badge (if no external disks attached)
3. **Expected**: Button shows eject icon WITH a red badge showing "0" or no badge

### Test 2: Mount One Disk
1. Connect an external USB drive or mount a disk image
2. Wait up to 3 seconds for the plugin to poll
3. **Expected**: Button updates to show red badge with "1"
4. **Expected**: Console log shows: `Disk count changed to: 1`

### Test 3: Mount Multiple Disks
1. Connect or mount 2-3 additional external disks
2. Wait up to 3 seconds after each mount
3. **Expected**: Badge updates to show "2", "3", etc.
4. **Expected**: Each update logs: `Disk count changed to: N`

### Test 4: Eject Functionality
1. With external disks mounted, press the Stream Deck button
2. **Expected**: Icon shows animated ejecting state with yellow color
3. **Expected**: Title changes to "Ejecting..." (if title is enabled)
4. **Expected**: After ejection, green checkmark appears briefly
5. **Expected**: Title shows "Ejected!" briefly
6. **Expected**: After 2 seconds, icon returns to normal with updated count (should be 0)
7. **Expected**: Badge disappears when count is 0

### Test 5: Real-time Monitoring
1. With the button on your Stream Deck, mount an external disk via Finder
2. Wait 3 seconds
3. **Expected**: Badge automatically updates without pressing the button
4. Eject the disk via Finder
5. Wait 3 seconds
6. **Expected**: Badge automatically updates/disappears

### Test 6: Multiple Button Instances
1. Drag the action to multiple keys on your Stream Deck
2. Mount/unmount external disks
3. **Expected**: All instances update simultaneously

### Test 7: Settings Test
1. Right-click the button and select "Settings"
2. Toggle the "Show text on button" checkbox
3. **Expected**: Title text appears/disappears immediately
4. **Expected**: Disk count badge remains visible regardless of title setting

## Debugging

### Enable Trace Logging
The plugin has `LogLevel.TRACE` enabled in `src/plugin.ts:6`, which logs all WebSocket messages between Stream Deck and the plugin.

### View Logs
- **Stream Deck Logs**: Open Stream Deck → Preferences → Advanced → Open Plugin Log
- Look for entries from "Eject All Disks plugin"
- Key log messages to look for:
  - `Eject All Disks plugin initializing`
  - `Disk count changed to: N`
  - `Ejecting disks...`
  - `Disks ejected: [output]`

### Common Issues

**Badge doesn't appear:**
- Check that you actually have external disks mounted (`diskutil list external` in Terminal)
- Check plugin logs for errors
- Restart Stream Deck software

**Count doesn't update:**
- Monitoring interval runs every 3 seconds, wait for the next poll
- Check if the action is visible (monitoring stops on `onWillDisappear`)
- Verify disk is actually listed as "external" by diskutil

**Ejection fails:**
- Disks may be in use by applications
- Check Console.app for diskutil errors
- Try ejecting via Finder first to see specific error messages

## Manual Disk Count Test

You can manually test the disk counting logic in Terminal:

```bash
# List all external disks
diskutil list external

# Count external disks (same command the plugin uses)
diskutil list external | grep -o -E '/dev/disk[0-9]+' | sort -u | wc -l
```

This should match the number shown on your Stream Deck button badge.

## Build Information

- **SDK Version**: 2.0.0-beta.2
- **Node.js Version**: 20
- **Minimum macOS**: 12 (Monterey)
- **Minimum Stream Deck Software**: 6.4
- **TypeScript Version**: 5.2.2
- **Rollup**: 4.0.2

## What Was Fixed

### Bug #1: Missing Disk Count Feature
The original code had no disk counting functionality. This update adds:
- Real-time monitoring of external disk count
- Visual badge display on the button icon
- Automatic updates every 3 seconds
- Proper cleanup when button is removed

### Bug #2: Timeout Cleanup Issue
Fixed duplicate timeout additions in error handler (line 292 of original code had three `this.timeouts.add(timeout)` calls).

### Bug #3: Icon Not Updating After Ejection
Updated all timeout handlers to call `updateDiskCount()` instead of just restoring the static icon, ensuring the badge reflects the current state.

## Package Contents

```
dist/org.deverman.ejectalldisks.streamDeckPlugin (443KB)
├── manifest.json (SDK version 2, Node.js 20)
├── bin/
│   └── plugin.js (267KB minified)
├── imgs/
│   ├── actions/eject/icon.svg
│   ├── actions/eject/state.svg
│   ├── icons/eject.svg
│   └── plugin/
│       ├── category-icon.png
│       ├── category-icon@2x.png
│       ├── marketplace.png
│       └── marketplace@2x.png
├── ui/
│   └── eject-all-disks.html
└── libs/
    ├── js/property-inspector.js
    └── css/sdpi.css
```

## Success Criteria

The plugin is working correctly if:
- ✅ Badge appears with correct disk count
- ✅ Badge updates automatically within 3 seconds of mounting/unmounting
- ✅ Badge disappears when count is 0
- ✅ Clicking button ejects all external disks
- ✅ Badge updates after ejection to show remaining disks (usually 0)
- ✅ No errors in plugin logs
- ✅ Multiple button instances stay synchronized
