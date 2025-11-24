# Eject All Disks - Privilege Setup Guide

This plugin uses macOS DiskArbitration framework for fast disk ejection. For the best experience, a one-time setup is required to allow the eject tool to run without password prompts.

## Quick Setup

1. Open **Terminal** (Applications → Utilities → Terminal)

2. Run the setup script:
   ```bash
   bash "/path/to/plugin/bin/install-eject-privileges.sh"
   ```

   The exact path depends on where Stream Deck installed the plugin. You can find it in the property inspector by clicking the action in Stream Deck and looking at the "Privilege Setup" section.

3. Enter your admin password when prompted

4. Done! The plugin will now eject disks without requiring a password each time.

## What Does the Setup Do?

The setup script creates a sudoers rule that allows the eject-disks binary to run with elevated privileges without requiring a password. This is safe because:

- Only the specific eject-disks binary is allowed to run without a password
- The binary only performs disk ejection operations
- The rule is scoped to your user account only
- No other commands or binaries are affected

The setup creates a file at `/etc/sudoers.d/eject-disks` with the following content:
```
YOUR_USERNAME ALL=(ALL) NOPASSWD: /path/to/eject-disks *
```

## Verifying Setup

After running the setup script, you can verify it works:

1. Open the property inspector in Stream Deck (click on the Eject All Disks action)
2. Look at the "Privilege Setup" section
3. Click "Check Status" - it should show "✓ Configured"

Or test from Terminal:
```bash
sudo -n /path/to/eject-disks --version
```

If configured correctly, this should print the version without asking for a password.

## Removing the Setup

To remove the passwordless execution privilege:

```bash
sudo rm /etc/sudoers.d/eject-disks
```

After removal, the plugin will still work but you may see authorization prompts when ejecting disks.

## Without Setup

The plugin will still work without the privilege setup, but:

- Disk ejection may fail with "Not privileged" errors for some volumes
- macOS may show authorization dialogs when ejecting certain disks
- Some disk images or encrypted volumes may not eject properly

For the most reliable experience, we recommend completing the setup.

## Troubleshooting

### Setup script not found
If the property inspector shows "Setup script not found", ensure the plugin is properly installed. Try reinstalling the plugin from Stream Deck.

### Permission denied
If you get a permission denied error when running the setup script, make sure you're running it with `bash` and that you have administrator privileges on your Mac.

### Sudo syntax error
If the sudoers configuration fails validation, the setup script will automatically remove the invalid configuration. Try running the setup script again.

### Disks still not ejecting
If disks still fail to eject after setup:
1. Make sure no applications are using files on the disk
2. Try closing all Finder windows
3. Use the force eject option if available
4. Check System Settings → Privacy & Security → Full Disk Access and ensure Stream Deck has access

## Security Considerations

This setup grants passwordless sudo access only for the specific eject-disks binary included with this plugin. It does not:

- Grant root access to any other commands
- Affect other users on the system
- Modify system security settings beyond the sudoers rule
- Store or transmit any credentials

The sudoers approach is the standard method used by many macOS tools that need elevated privileges for specific operations.
