# SafeEject v4.0.0 — confirmed ejection and faster failure feedback

SafeEject 4.0.0 is a reliability-focused architecture release. It requires
macOS 26 or later; macOS 13–15 are no longer supported. Stream Deck 6.9 remains
the minimum supported Stream Deck version.

## What you will notice

- **Success now means macOS confirmed the physical eject.** `Ejected!` appears
  only after the whole disk unmounts and the subsequent `DADiskEject` callback
  succeeds. An empty mounted-volume count is never treated as proof that a disk
  is safe to unplug.
- **Known failures appear immediately.** If macOS reports that a disk is busy,
  permission is denied, or another definitive error occurs, SafeEject shows it
  as soon as the callback arrives. It does not wait for a timeout first. The
  failure display then yields to the live disk count at the next inventory
  refresh — a mount/unmount/wake notification or the 30-second fallback check —
  so the key never stays stuck on a stale error.
- **Long operations explain themselves.** A pending stage changes to
  `Working…` after 3 seconds and `Check Disk` after 15 seconds, so the key
  does not look frozen while macOS is still working.
- **The 30-second value is an exceptional watchdog, not the expected delay.**
  Whole-disk unmount has an absolute 25-second ceiling. A successful unmount
  proceeds immediately to eject, which may use only the time remaining before
  the original 30-second overall deadline.
- **Timeout is deliberately cautious.** DiskArbitration cannot cancel an
  already-submitted operation. `Timeout` or `Check Disk` means SafeEject stopped
  waiting without confirmation; it does not claim that macOS cancelled the
  request or that the disk is safe to remove.
- **First paint is truthful.** A newly visible key shows `Checking…` until a
  fresh disk enumeration completes. Session failure shows `Failed`, never an
  invented `No Disks` result.
- **Disk counts remain responsive without aggressive polling.** Mount,
  unmount, rename, and wake notifications trigger refreshes, with a
  subscriber-only 30-second fallback check for missed events.

## Reliability work under the hood

- Replaced retained Swift callback pointers with opaque integer cookies and a
  mutex-protected registry. Callback, timeout, and cancellation race through
  one exactly-once completion path; late and duplicate C callbacks are harmless.
- Replaced wall-clock timing with `ContinuousClock` absolute deadlines.
- Added per-physical-device progress, so one disk's immediate busy result is
  visible while other disks continue ejecting concurrently.
- Replaced mutable action fields and unrelated callback tasks with a sequenced
  event ingress, a coordinator actor, and a pure enum-driven state reducer.
- Added action-instance tokens, monitor generations, operation IDs, and render
  revisions so stale lifecycle or callback work cannot update a vanished or
  reused Stream Deck context.
- Upgraded repository-owned code to Swift 6.3.3 language mode with complete
  concurrency checking, strict memory-safety diagnostics, warnings-as-errors,
  explicit public `Sendable` declarations, and debug actor race checks.
- Pinned the reviewed StreamDeckPlugin dependency revision. Its older
  annotations remain isolated behind a narrow, explicitly audited import and
  actor-serialized transport boundary.

## Safety boundaries

SafeEject continues to use non-forced unmount by default. It does not scan for
or name applications that hold files open in 4.0.0, though structured device,
stage, error-category, and raw-status data are now preserved for a future
blocker-diagnostics interface. No new permissions are required; Stream Deck
still needs Full Disk Access for reliable disk operations.

No software can protect against cable removal, power loss, firmware failure,
or defective hardware. A successful `DADiskEject` callback is the strongest
safe-to-remove confirmation exposed by macOS.
