# SafeEject v3.0.4 — Instant disk counts and no more hangs

A bug-fix and performance release. No settings changes required — update and go.

## What you'll notice

- **Disk count updates instantly.** The key now reacts the moment a drive is
  plugged in or removed, instead of catching up on a 3-second polling cycle.
  The count also appears immediately when the key first shows up, with no
  startup delay. Idle CPU cost drops to zero — the plugin listens for macOS
  mount events rather than rescanning your volumes every few seconds.
- **The eject display no longer flickers.** Previously the button could
  briefly show "No Disks" in the middle of an eject before flipping to
  "Ejected!". The Ejecting… → Ejected! sequence is now stable.
- **A stuck drive can't freeze the button anymore.** Eject operations now have
  an enforced 30-second limit per drive (down from a worst case of 60 — and,
  due to a bug, potentially forever). If a drive doesn't respond, you get a
  clear "Timeout" instead of a spinner that never ends.
- **More dependable error messages.** "In Use", "Timeout", and "Grant Access"
  hints are now driven by the system's actual error codes instead of matching
  error message text, so you'll see the right hint every time.

## Under the hood

- Fixed a concurrency bug where the operation timeout could never actually
  fire, leaving the plugin waiting indefinitely on an unresponsive drive.
- The plugin now degrades gracefully (error state on the key) instead of
  crashing if the DiskArbitration session cannot be created.
- Volume discovery uses macOS's canonical mounted-volumes API end to end;
  system, network, and hidden volumes are excluded via system APIs, never by
  name.
- Disk-eject failures now carry typed error categories through the whole
  stack, with expanded test coverage (97 tests across the plugin and the
  SwiftDiskArbitration library).
