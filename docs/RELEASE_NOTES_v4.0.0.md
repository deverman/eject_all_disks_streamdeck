# SafeEject v4.0.0 — confirmed ejection and faster failure feedback

SafeEject 4.0.0 is a reliability-focused architecture release. It requires
macOS 26 or later; macOS 13–15 are no longer supported. Stream Deck 6.9 remains
the minimum supported Stream Deck version.

## Marketplace update

- Confirmed safe ejection: success appears only after macOS confirms the
  physical device was ejected, including APFS-backed drives.
- Faster, clearer feedback: busy disks show `In Use` immediately, while longer
  operations display `Working…` and `Check Disk`.
- Better multi-drive reliability: SafeEject handles multiple disks concurrently
  and reports mixed success or failure honestly.
- More responsive disk status: mount, unmount, rename, and wake events update
  the key without aggressive polling.
- Requires macOS 26 or later and Stream Deck 6.9 or later.

## What you will notice

- **Success now means macOS confirmed the physical eject.** `Ejected!` appears
  only after SafeEject resolves synthesized storage such as an APFS container
  into an ordered whole-media stack, unmounts its mounted branches, ejects
  synthesized layers from inner to outer, and finally receives a successful
  `DADiskEject` callback for the physical device. An empty mounted-volume count
  is neutral and never shows a green confirmation or acts as proof that a disk
  is safe to unplug.
- **Known failures appear immediately.** If macOS reports that a disk is busy,
  permission is denied, or another definitive error occurs, SafeEject shows it
  as soon as the callback arrives. It does not wait for a timeout first. The
  actionable failure remains visible until you press the key to retry or a real
  mount, unmount, rename, or wake event changes the disk topology. The
  30-second drift check cannot silently erase the last failure.
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
- Added public-API I/O Registry ancestry resolution so APFS volumes eject each
  synthesized whole-media layer before their physical store. Multiple storage
  branches on one device are deduplicated into one ordered workflow. Every
  copied IOKit handle is released exactly once; ambiguous multi-parent storage
  graphs fail closed instead of selecting one member.
- Added privacy-safe unified logs for the resolved BSD layer order, operation
  stage and target, typed result category, raw DiskArbitration status, and
  elapsed time. Terminal successes use persistent notice records; failures,
  timeouts, and cancellations use persistent error records. Volume names and
  paths are never logged.
- Decode Disk Arbitration's documented BSD-encoded statuses, including
  `unix_err(EBUSY)`, so busy vnodes and applications reliably show `In Use`
  instead of a generic failure.
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
