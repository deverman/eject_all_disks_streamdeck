# SafeEject: One-Push Disk Manager - Permissions Setup

This plugin ejects disks using macOS’s native DiskArbitration APIs. It does **not** install helpers, create sudoers rules, or require `sudo`.

## Required Permission: Full Disk Access

Disk ejection can be blocked by macOS privacy protections unless the Stream Deck app has **Full Disk Access**.

1. Open **System Settings**
2. Go to **Privacy & Security** → **Full Disk Access**
3. Add/enable: `/Applications/Elgato Stream Deck.app`
4. Restart Stream Deck

If you are running the plugin binary directly for development, you may need to grant Full Disk Access to the plugin executable in:

`~/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/org.deverman.ejectalldisks`

## Troubleshooting

- **Button shows “Grant Access” / eject fails:** verify Full Disk Access and restart Stream Deck.
- **Disk says “In Use”:** close apps using the disk (Spotlight indexing, backup/sync tools, Finder windows) and try again.
- **No disks detected:** only external/ejectable volumes are counted; network shares and internal volumes are excluded.

## Logs

View plugin logs with:

```bash
log stream --predicate 'subsystem == "org.deverman.ejectalldisks"'
```
