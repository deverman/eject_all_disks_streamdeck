# SafeEject 4.0.0 correctness and architecture plan

- Status: corrected build installed, automated validation passed, and physical
  UAT approved for release on 2026-08-06; merge and publication are in progress
- Target branch: `eject-reliability-instant-counts`
- Target release: SafeEject `4.0.0` / Stream Deck manifest version `4.0.0.0`
- Required development toolchain: Swift `6.3.3` or newer in the Swift 6 language mode
- Minimum runtime: macOS 26
- Minimum Stream Deck: 6.9
- Audience: an implementation agent with limited prior context

Implementation checkpoint (2026-07-27): live Disk Arbitration logs first proved
that the prior candidate ejected synthesized APFS `disk7` while physical USB
`disk6` remained online. The first correction then resolved only `disk6`; UAT
failed safely because macOS requires the synthesized APFS whole disk to be
ejected before its physical store. A manual `diskutil eject disk6` trace
confirmed the required sequence: unmount `disk7`, eject `disk7`, then eject
`disk6`. The branch now resolves every whole-media ancestor, merges multiple
branches per physical device, and submits unmount/eject work inner-to-outer.
Only the final physical callback can produce green feedback. Privacy-safe
structured OSLog records now retain the BSD layer order, stage, target,
category, raw status, and duration.

A later three-disk soak test completed two full concurrent eject cycles, then
correctly refused to unmount two busy APFS volumes on a third cycle while the
independent third disk ejected successfully. macOS reported BSD `EBUSY` as
`unix_err(EBUSY)` (`0x0000C010`), which the library preserved but classified as
`.other`. The correction now decodes documented BSD-wrapped Disk Arbitration
statuses so this case presents `In Use`. It also persists terminal success at
OSLog notice level and failures/timeouts/cancellations at error level after
short-lived info records proved insufficient for multi-day diagnostics.
Library tests pass with 60 tests normally, under AddressSanitizer, and under
ThreadSanitizer. The plugin passes 91 tests normally and under ThreadSanitizer.
The release build passed bundle validation, its installed SHA-256 matched the
built artifact, and Stream Deck loaded the replacement process with clean
startup and monitor records. Fresh physical three-disk UAT completed all devices
concurrently through their inner APFS and outer physical layers. Continued use
of the installed build was approved for release on 2026-08-06. A dedicated
Instruments recording remains formally unchecked; the owner chose to proceed
based on the sanitizer, deterministic regression, installed-binary, runtime-log,
and extended physical-use evidence. No tag, merge, or release publication has
occurred.

## 1. Objective

Prepare a release that makes the strongest claim macOS allows: when SafeEject
shows a successful eject result, macOS has confirmed completion of the
whole-device eject operation. The release must also remain responsive when a
disk is busy or the DiskArbitration service/device fails to answer.

This plan must solve all five previously identified areas:

1. Leak-free DiskArbitration callback bridge.
2. Strict monotonic per-device deadline.
3. Race-free Stream Deck action and lifecycle handling.
4. Fresh, truthful first paint and disk-count monitoring.
5. Swift 6.3.3, macOS 26, CI, and release metadata migration.

It also replaces the current collection of booleans and imperative display
writes with a typed, enum-driven state machine. The new model must preserve
structured failure information so a later release can identify applications or
processes blocking an eject without redesigning the ejection pipeline.

## 2. Definition of done

The release is complete only when all of the following are true:

- A missing DiskArbitration callback cannot retain a Swift object forever.
- Callback, timeout, and cancellation can race without double-resuming a
  continuation or accessing freed memory.
- Every duration and deadline uses a monotonic clock.
- A physical device operation never waits longer than its documented hard
  budget inside SafeEject.
- A DiskArbitration dissenter is shown as soon as it arrives; there is no
  artificial wait for a timeout.
- The key gives progressive feedback at 3 and 15 seconds while preserving a
  30-second final watchdog ceiling.
- A mounted-volume count of zero cannot be mistaken for confirmed eject
  success while an eject operation is still active.
- Only a successful `DADiskEject` callback can produce SafeEject's successful
  `Ejected!` / safe-to-remove state.
- An action that disappears cannot receive or render later monitor, settings,
  or eject callbacks.
- A newly visible key never paints an invented or stale zero before its first
  fresh disk enumeration.
- All repository-owned targets compile in Swift 6 language mode with complete
  concurrency checking.
- Strict memory-safety diagnostics are enabled and every unsafe C operation is
  narrowly acknowledged and documented.
- The StreamDeck dependency remains behind a narrow `@preconcurrency` boundary;
  repository-owned mutable state does not rely on that annotation.
- Both test suites, release builds, sanitizers, Stream Deck validation,
  packaging, and physical-device UAT pass.
- Release metadata consistently says 4.0.0, macOS 26, and Swift 6.3.3.

## 3. Scope and non-goals

### In scope

- DiskArbitration callback memory ownership and cancellation safety.
- Absolute monotonic deadlines and progressive operation events.
- Per-physical-device progress from batch ejection.
- A pure state reducer and ordered runtime coordinator.
- Stream Deck appearance, disappearance, settings, key, and rendering
  lifecycle correctness.
- Disk-count monitoring, cache validity, wake recovery, and first-paint truth.
- Typed stage/category/status information for failures.
- Swift 6.3.3 compiler enforcement and macOS 26 deployment.
- Deterministic unit/integration tests and real-device release validation.
- Release notes and compatibility documentation.

### Explicit non-goals for 4.0.0

- Do not identify blocking PIDs or application names.
- Do not run `lsof`, scan process file descriptors, or add a privileged helper.
- Do not add a new window, panel, notification, or Property Inspector workflow.
- Do not add force-eject behavior. SafeEject continues to use non-forced
  unmounting by default because forced unmount can cause data loss.
- Do not add automatic retry loops for busy disks. A busy result is actionable
  and must be surfaced immediately; the user can close the responsible app and
  press the key again.
- Do not convert the raw Stream Deck executable into an app bundle.
- Do not change stable plugin or action UUIDs.
- Do not modify the third-party StreamDeck package to make it Swift 6 clean in
  this release.
- Do not log volume names, mount paths, file paths, application names, or other
  private disk contents.

## 4. Verified current state

These are repository facts at the time this plan was written:

- Branch: `eject-reliability-instant-counts`.
- Both package manifests declare `// swift-tools-version: 5.9`.
- The current compiler is Swift 6.3.3, but both packages currently compile in
  Swift 5 language mode.
- Both packages currently target macOS 13.
- GitHub Actions currently uses `macos-14` and Swift 6.2.1.
- The plugin currently advertises version `3.0.4.0` and macOS 13.
- `EjectAction` stores mutable `diskCount` and `showTitle` properties and
  captures the action instance from untracked tasks.
- `DiskCountMonitor` is `@MainActor`, starts with `lastCount = 0`, publishes that
  value before a fresh refresh, and retains it while monitoring is stopped.
- `CallbackBridge` passes a retained `DiskCallbackContext` pointer to
  DiskArbitration. If DiskArbitration never calls back, the retained context is
  never released.
- The combined unmount/eject implementation measures time with `Date` and can
  grant eject an additional five seconds after unmount consumed the nominal
  30-second budget.
- `DiskSession.ejectAll` processes physical devices concurrently but returns
  progress only after every device has completed. One slow device can therefore
  hide another device's immediate busy result.
- The current plugin has no central state enum or reducer.
- A strict-memory-safety compiler probe correctly fails at the current unsafe
  sites, including the raw callback pointer, `DADiskGetBSDName`, the
  `nonisolated(unsafe)` session property, and C variadic string formatting.
- The bundled `streamdeck-swift-builder doctor` passes with Swift 6.3.3,
  macOS 26.5.2, Stream Deck CLI, Node, repository structure, and git cleanliness.

Previous validation established a baseline of 62 plugin tests and 35 library
tests. Those numbers are a baseline, not a release gate; the final counts will
increase.

## 5. Apple API contract and the user safety promise

The implementation must preserve the storage dependency sequence observed from
macOS's native whole-device eject:

1. Obtain the volume's `IOMedia` with `DADiskCopyIOMedia`.
2. Walk its parents in the I/O Registry service plane and retain every whole
   `IOMedia`, because Apple defines whole media as a physical disk or a virtual
   replica.
3. Merge branches that share the same outermost physical device, preserving
   every inner-before-outer dependency and deduplicating shared layers.
4. Create each `DADisk` with `DADiskCreateFromIOMedia`. If ancestry is
   unavailable, exceeds its bound, or has multiple parents, fail closed without
   submitting an eject request.
5. Call `DADiskUnmount` with `kDADiskUnmountOptionWhole` for each distinct
   innermost mounted whole-media branch and wait for every callback.
6. If a callback contains a dissenter, stop and report the typed failure.
7. Eject each unique whole-media layer from inner to outer under the original
   absolute deadline. For common APFS storage this is virtual `disk7`, then
   physical `disk6`.
8. Stop immediately if any eject callback contains a dissenter.
9. Treat only the outermost physical eject callback with no dissenter as the
   authoritative safe-to-remove signal.

Authoritative references:

- [Apple Disk Arbitration: Manipulating Disks and Volumes](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ManipulatingDisks/ManipulatingDisks.html)
- [DADiskUnmount callback contract](https://developer.apple.com/documentation/diskarbitration/dadiskunmountcallback)
- [DAReturn error categories](https://developer.apple.com/documentation/diskarbitration/dareturn)
- [Disk Arbitration notification and approval behavior](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ArbitrationBasics/ArbitrationBasics.html)

### Required safety semantics

- Successful whole-disk unmount is an internal transition to `unmounted`; it is
  not SafeEject's final success signal.
- Successful physical eject is the transition to `safeToRemove`.
- A DiskArbitration disappearance callback cannot substitute for eject success.
  macOS also emits disappearance when hardware is unplugged unexpectedly, so
  disappearance alone cannot prove that the preceding removal was safe.
- A mounted-volume inventory count of zero is not an eject-operation result.
- While an operation is active, its state takes presentation priority over the
  inventory state. A temporary zero must never overwrite `unmounting`,
  `ejecting`, `failed`, or `timedOut`.
- If unmount succeeds but eject fails or times out, do not show `Ejected!` and
  do not immediately fall back to normal `No Disks`. The operation must remain
  visibly unconfirmed (`Check Disk` or `Timeout`) until a retry or a later
  topology lifecycle reset.
- No software can guarantee against device firmware failure, power loss, cable
  removal, or hardware defects. The successful `DADiskEject` callback is the
  strongest confirmation the macOS API provides.

## 6. User-response timing policy

The 30-second value is a hard failure watchdog, not a normal delay and not a
debounce before reporting an error.

### Required timeline per physical device

- At `t = 0`: submit the real whole-disk unmount immediately.
- If macOS returns a dissenter at any time: publish the failure immediately.
  Do not wait for 3, 15, 25, or 30 seconds.
- At `t = 3s`, if still pending: transition the active stage's wait status from
  `normal` to `slow`; the key may show `Working…`.
- At `t = 15s`, if still pending: transition to `attention`; the key shows
  `Check Disk` while the operation continues.
- At `t = 25s`, if whole-disk unmount is still pending: finish SafeEject's wait
  with an unmount timeout. Do not submit physical eject because there is no
  confirmed unmount.
- If unmount succeeds before 25 seconds: submit physical eject immediately.
- Physical eject may use all remaining time until the absolute `t = 30s`
  deadline; it is not capped at exactly five seconds when unmount is fast.
- At the absolute `t = 30s` deadline: finish SafeEject's wait with an eject
  timeout if eject is still pending.

The two stage deadlines are therefore:

```text
operation start
    |
    +-- unmount deadline = start + 25 seconds
    |
    +-- overall/eject deadline = start + 30 seconds
```

DiskArbitration has no cancellation parameter for a submitted unmount or eject.
A SafeEject timeout means "the plugin stopped waiting without confirmation," not
"macOS cancelled the device operation." A late C callback must be memory-safe
and must not overwrite a newer operation or action instance.

## 7. Target architecture

Use four layers with one-way dependencies:

```text
Stream Deck callbacks / NSWorkspace / DiskArbitration callbacks
                         |
                         v
              Sequenced event ingress
                         |
                         v
                EjectCoordinator actor
                         |
              pure EjectState reducer
                         |
                         v
              KeyPresentation values
                         |
                         v
            StreamDeckRenderer / transport
```

The DiskArbitration library remains below the plugin coordinator:

```text
DiskSession actor
    |
    +-- volume and physical-device discovery
    +-- per-device unmount/eject workflow
    +-- DeviceEjectEvent progress values
    +-- DiskOperationRegistry (Mutex + opaque callback tokens)
    +-- ContinuousClock deadlines
```

### Layer responsibilities

#### Disk operation layer

- Owns DiskArbitration session and `DADisk` operations.
- Converts C callbacks into safe asynchronous results.
- Applies stage deadlines.
- Emits typed per-device progress.
- Never imports StreamDeck and never chooses user-facing titles or images.

#### Pure state engine

- Defines exhaustive enums and value types.
- Reduces `(state, event)` into a new state and effects.
- Derives a presentation value from current state.
- Has no clocks, C pointers, observers, tasks, or Stream Deck calls.

#### Runtime coordinator

- Owns the state engine in one actor.
- Starts/cancels Swift tasks and routes resulting events back through ingress.
- Rejects stale operation IDs, action-instance tokens, generations, and render
  revisions.
- Coordinates shared disk inventory monitoring across all visible keys.

#### Action/renderer edge

- `EjectAction` conforms to the StreamDeck protocol but remains nonisolated.
- It submits immutable `Sendable` event snapshots and does not own mutable
  business state.
- The renderer converts `KeyPresentation` into Stream Deck commands.
- Only this edge imports StreamDeck with `@preconcurrency`.

## 8. State model

The exact names may change for Swift style, but the cases and distinctions must
not be collapsed.

```swift
enum EjectCoordinatorState: Sendable, Equatable {
    case inactive
    case checking(VisibleActions)
    case ready(DiskInventoryState)
    case ejecting(BatchEjectState)
    case completed(BatchEjectSummary)
}

enum DiskInventoryState: Sendable, Equatable {
    case checking
    case available(ejectableVolumeCount: Int)
    case unavailable
}

enum WaitStatus: Sendable, Equatable {
    case normal
    case slow
    case attention
}

enum DiskOperationStage: String, Sendable, Codable, Hashable {
    case unmount
    case eject
}

enum DeviceEjectState: Sendable, Equatable {
    case queued
    case unmounting(WaitStatus)
    case unmounted
    case ejecting(WaitStatus)
    case safeToRemove
    case failed(DeviceEjectFailure)
    case timedOut(stage: DiskOperationStage)
    case cancelled
    case disappearedWithoutEjectConfirmation
}
```

`disappearedWithoutEjectConfirmation` records the observable fact without
claiming that removal was safe. It must never be converted into `safeToRemove`.

### Identifiers and stale-result rejection

```swift
struct EjectOperationID: Hashable, Sendable { /* UUID or monotonic ID */ }
struct ActionInstanceID: Hashable, Sendable { /* UUID */ }
struct PhysicalDeviceID: Hashable, Sendable { let bsdName: String }
struct SubscriptionID: Hashable, Sendable { /* monotonic token */ }
```

- Every eject event contains `EjectOperationID` and `PhysicalDeviceID`.
- Every render request contains `ActionInstanceID` and a monotonically
  increasing revision.
- Every monitor subscriber has a unique `SubscriptionID`, even when a Stream
  Deck context string is reused.
- A disappearance can remove only its matching subscription token.
- The coordinator ignores operation events whose operation ID is no longer
  current.
- The renderer ignores commands whose action token is no longer active or
  whose revision is older than the latest accepted revision.

### Typed failures for future blocker diagnostics

```swift
struct DeviceEjectFailure: Sendable, Equatable {
    let deviceID: PhysicalDeviceID
    let stage: DiskOperationStage
    let category: DiskErrorCategory
    let rawStatus: DAReturn?
}
```

Do not add PID or app models yet. Preserving device, stage, typed category, and
raw status is enough for a later diagnostic layer to decide when a `.busy`
failure warrants process inspection. Never require downstream code to parse
localized error strings.

### Batch state and aggregation

`BatchEjectState` stores a dictionary keyed by physical device ID. Volumes on
the same whole disk share one device state and one unmount/eject workflow.

Required aggregate rules:

- All physical devices begin concurrently.
- Per-device progress is published as it happens.
- A definitive failure is immediately eligible for display even while other
  devices continue.
- Overall success requires every requested device to reach `safeToRemove`.
- A mixture of safe and failed devices is a partial failure, never overall
  success.
- The final summary preserves per-device and per-volume results.

## 9. Pure reducer and effects

Define an `EjectEvent` enum containing every external stimulus:

```swift
enum EjectEvent: Sendable {
    case actionAppeared(ActionAppearance)
    case actionDisappeared(ActionDisappearance)
    case settingsChanged(ActionSettingsSnapshot)
    case keyReleased(ActionKeyRelease)
    case inventoryRefreshRequested(InventoryRefreshReason)
    case inventoryResolved(generation: UInt64, DiskInventoryState)
    case operationStarted(EjectOperationID, [PhysicalDeviceID])
    case deviceProgress(EjectOperationID, DeviceEjectEvent)
    case slowThresholdReached(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case attentionThresholdReached(EjectOperationID, PhysicalDeviceID, DiskOperationStage)
    case operationCompleted(EjectOperationID, BatchEjectResult)
    case systemWoke
}
```

The reducer returns state plus explicit effects:

```swift
struct EjectReduction: Sendable {
    let state: EjectCoordinatorState
    let effects: [EjectEffect]
}
```

Possible effects include starting/stopping inventory monitoring, enumerating
volumes, beginning an eject operation, and rendering a presentation. Effects
must return their results as new sequenced events; they may not mutate state
directly.

Reducer invariants:

- Invalid transitions are ignored or recorded as internal diagnostics, never
  coerced into a plausible state.
- A stale operation cannot change the active operation.
- Inventory events update stored inventory but cannot replace an active
  operation presentation.
- `safeToRemove` is reachable only from an eject-success event.
- A dissenter is terminal for that stage and device.
- A timeout is indeterminate and never converted to success based on elapsed
  time or a zero volume count.
- Settings changes update future presentation immediately without restarting
  disk operations.
- Action disappearance invalidates its rendering token synchronously.

## 10. Ordered event ingress

Do not create unrelated `Task {}` blocks in each Stream Deck callback and assume
they will execute in callback order.

Implement a process-local `EventIngress`:

- Store a monotonic event sequence and an `AsyncStream` continuation behind
  `Synchronization.Mutex`.
- Assign and yield each event while holding the mutex so events have one total
  submission order.
- Use one long-lived coordinator consumer task to read the stream.
- Do not use a buffering policy that may discard lifecycle events.
- The stream and consumer live for the plugin process lifetime; action objects
  are not retained by either.
- Values submitted to ingress must be `Sendable` snapshots. Never submit the
  action instance, AppKit objects, `DADisk`, or mutable closures capturing them.

This serialization boundary supplements Swift's type-system checking at the
unannotated StreamDeck protocol edge.

## 11. Leak-free DiskArbitration callback bridge — defect #1

### Problem

The current bridge uses:

```swift
Unmanaged.passRetained(context).toOpaque()
```

The retain is balanced only if DiskArbitration invokes the callback. A watchdog
resumes the continuation but cannot release that pointer safely because a late C
callback could then dereference freed memory. The current code therefore accepts
a permanent allocation leak for every callback that never arrives.

### Required design

Replace object pointers with opaque numeric tokens:

```swift
final class DiskOperationRegistry: Sendable {
    private let state: Mutex<State>
}

private struct State: Sendable {
    var nextToken: UInt = 1
    var pending: [UInt: PendingDiskOperation] = [:]
}
```

The context pointer is an encoded nonzero integer token. DiskArbitration treats
the context as opaque and echoes it to the callback; the callback must never
dereference it as memory.

### Operation registration

1. Allocate a nonzero token under the mutex.
2. Skip any token already in `pending`; handle `UInt` rollover explicitly.
3. Insert the continuation, monotonic start instant, operation kind, and
   watchdog handle under that token.
4. Encode the integer as the C context pointer inside one audited unsafe adapter.
5. Call `DADiskUnmount` or `DADiskEject`.

### Completion arbitration

Callback, watchdog, and cancellation all call one registry completion method:

1. Atomically remove the pending record under the mutex.
2. If no record exists, the event lost the race and returns without action.
3. Cancel the watchdog when callback/cancellation wins.
4. Release the mutex.
5. Resume the continuation outside the mutex.

Never call a continuation, actor, logger that can re-enter, or arbitrary closure
while holding `Mutex`.

### Timeout behavior

- Timeout removes the registry entry before resuming `.timeout`.
- The registry must expose an internal pending-count snapshot for tests.
- A late callback decodes its token, finds no entry, and safely returns.
- Repeated callbacks for one token safely no-op.
- There is no retained Swift callback object for a never-returning C operation.

### Task cancellation

Wrap the bridge with `withTaskCancellationHandler`:

- If cancellation happens before the C call is submitted, return `.cancelled`
  without submitting the operation.
- If it happens after submission, atomically remove/resume through the same
  registry path.
- Cancellation cannot cancel DiskArbitration itself. Any later callback is a
  harmless loser of the registry race.

### Unsafe boundary

Create one small internal adapter responsible for:

- Token-to-`UnsafeMutableRawPointer` conversion.
- Pointer-to-token conversion.
- Calling `DADiskUnmount` and `DADiskEject` with the C callbacks.
- Reading `DADissenter` status.

Annotate/acknowledge only those expressions required by Swift strict memory
safety. Document why the pointer is never dereferenced and why zero is reserved.
Do not spread `unsafe` acknowledgements across the library.

## 12. Strict monotonic deadline — defect #2

### Problem

- `Date` is a wall clock and can move due to user, network, or system changes.
- The existing combined workflow gives unmount a full nominal budget and then
  uses `max(5, remaining)`, allowing the operation to exceed 30 seconds.
- A timeout result does not cancel the submitted DiskArbitration operation.

### Required design

- Use `ContinuousClock` in production.
- Define absolute instants once at operation start.
- Pass absolute deadlines down to low-level wrappers instead of passing relative
  timeout seconds that can be accidentally restarted.
- Keep the public `TimeInterval` duration fields for source compatibility, but
  derive them from monotonic `Duration` values at the API boundary.

Suggested internal form:

```swift
struct DeviceOperationDeadlines<C: Clock>: Sendable
where C.Duration == Duration, C.Instant: Sendable {
    let startedAt: C.Instant
    let unmountDeadline: C.Instant
    let overallDeadline: C.Instant
}
```

Production values:

```swift
let startedAt = clock.now
let unmountDeadline = startedAt.advanced(by: .seconds(25))
let overallDeadline = startedAt.advanced(by: .seconds(30))
```

Rules:

- The whole-disk unmount wrapper uses `unmountDeadline`.
- After unmount success, eject uses the original `overallDeadline`.
- If `clock.now >= deadline` before a C call, return timeout without submitting
  that call.
- At an exact callback/deadline race, the first successful registry removal is
  the winner. Tests must control event ordering rather than depending on the
  scheduler.
- Standalone unmount/eject APIs may retain a 30-second single-stage default but
  must still use an absolute monotonic deadline.
- Batch duration must also move from `Date` to `ContinuousClock`.

### Test clock

Make the operation coordinator generic over `Clock` where practical. Tests use
a manual clock that advances explicitly. Do not use `Task.sleep` in deadline
unit tests.

## 13. Per-device progress and fast failure

Extend the library with a typed progress path while preserving the existing
convenience API.

Suggested API shape:

```swift
public enum DeviceEjectEvent: Sendable {
    case unmountStarted(PhysicalDeviceID)
    case unmountCompleted(PhysicalDeviceID)
    case ejectStarted(PhysicalDeviceID)
    case completed(PhysicalDeviceID, DeviceEjectOutcome)
}

public func ejectAll(
    _ volumes: [Volume],
    options: EjectOptions = .default,
    onProgress: @escaping @Sendable (DeviceEjectEvent) async -> Void
) async -> BatchEjectResult
```

The existing overload without progress delegates to this method with a no-op
progress receiver.

Requirements:

- Group partitions by whole physical device before task creation.
- Start one child task per physical device.
- Emit progress at stage transitions.
- Await progress delivery only through a lightweight actor/event-ingress call;
  do not do rendering or diagnostics inside the library task.
- A busy dissenter from one task becomes visible immediately without waiting
  for the task group to finish other devices.
- No automatic preflight blocker scan delays the happy path.

## 14. Race-free Stream Deck lifecycle — defect #3

### Problem

- StreamDeck callbacks mutate `showTitle` while main-actor monitor callbacks read
  it.
- `diskCount` is written asynchronously and read by unrelated callbacks.
- `@preconcurrency import StreamDeck` suppresses missing dependency annotations
  but does not synchronize repository-owned state.
- Independent `Task { @MainActor ... }` calls in `willAppear` and
  `willDisappear` are not guaranteed to run in submission order.
- A fast disappear can be processed before a delayed subscribe, leaving a stale
  subscriber and active monitor.

### Required action edge

`EjectAction` should contain only protocol-required identifiers and immutable
handles:

- Stream Deck `context` and coordinates.
- A unique `ActionInstanceID`.
- A reference to `EventIngress`.

It must not retain mutable disk count, current operation status, settings, or a
monitor callback.

Each callback constructs a value snapshot and submits it synchronously:

- `willAppear` submits context, instance ID, device, decoded settings, and
  appearance information.
- `willDisappear` submits the same instance ID for conditional removal.
- `didReceiveSettings` submits the new `Sendable` settings value.
- `keyUp` submits context, instance ID, long-press flag, and settings snapshot.

Async tasks started by coordinator effects capture only values, actor references,
and operation IDs. They never capture `EjectAction` or `self`.

### Subscription tokens

- Appearance creates a new `SubscriptionID` for its action instance.
- Disappearance removes a subscription only when both context and token match.
- A late disappearance from an old instance cannot remove a newer instance that
  reused the same Stream Deck context.
- The final subscriber leaving schedules monitor resource shutdown.

### Observer lifecycle

AppKit/NSWorkspace observer and timer ownership stays on `MainActor`.
Start/stop reconciliation carries a monotonically increasing lifecycle epoch:

- An older delayed start cannot resurrect monitoring after a newer stop.
- An older delayed stop cannot tear down monitoring after a newer start.
- Observer tokens and the fallback timer are released after the final
  subscriber leaves.

### Rendering

Define a `KeyPresentation: Sendable, Equatable` value containing title, image
resource, and optional feedback command. A renderer actor owns transport order.

- Render commands carry action instance ID and revision.
- The renderer rejects inactive instance IDs and lower revisions.
- Stream Deck calls remain at this edge.
- Image decoding through AppKit occurs on `MainActor`; encoded/transport values
  crossing actors must be `Sendable`.
- Multiple placed keys receive the same operation state without retaining one
  another.

### Global eject gate

Replace `EjectOperationState: @unchecked Sendable` and `NSLock` with either:

- The coordinator actor's single active operation invariant; or
- A small `Synchronization.Mutex<ActiveOperation?>` admission gate if synchronous
  key-callback admission is required.

Do not keep both sources of truth. The coordinator state is authoritative.

## 15. Fresh first paint and monitor state — defect #4

### Problem

`DiskCountMonitor.lastCount` starts at zero and is immediately sent to a new
subscriber before fresh enumeration. The value also remains cached while the
monitor has no subscribers and therefore cannot observe offline disk changes.

### Required monitor behavior

- Replace implicit `Int` state with `DiskInventoryState`:
  - `.checking`
  - `.available(ejectableVolumeCount:)`
  - `.unavailable`
- The first subscriber after an idle period receives `.checking`, not zero.
- With titles enabled, `.checking` renders exactly `Checking…`.
- With titles disabled, `.checking` renders no title.
- Trigger fresh enumeration immediately after first subscription.
- A second subscriber joining while monitoring is continuously active may
  receive the current valid `.available` snapshot immediately.
- When the final subscriber leaves:
  - stop observers and timer;
  - cancel or invalidate in-flight refresh work;
  - increment the refresh generation;
  - clear the cached inventory so it cannot be reused later.
- If `DiskSession.shared` is unavailable, publish `.unavailable` and render
  `Failed`; never convert session failure into zero disks.
- A refresh result may publish only when its generation is still current.

### Refresh triggers

While at least one key is visible, refresh for:

- `NSWorkspace.didMountNotification`.
- `NSWorkspace.didUnmountNotification`.
- `NSWorkspace.didRenameVolumeNotification`.
- `NSWorkspace.didWakeNotification`.
- Explicit post-operation refresh.
- A 30-second low-frequency fallback poll in case a notification is missed.

The fallback timer is intentionally retained for resilience. Release notes must
not claim literal zero idle CPU while a key is visible; they should say the old
three-second poll was replaced by event-driven updates plus a low-frequency
drift check.

### Operation versus inventory presentation

Inventory may continue refreshing during an eject, but it cannot directly
render over operation state. The reducer stores the latest inventory and derives
presentation with this priority:

1. Active/terminal unconfirmed eject state.
2. Confirmed completed eject result.
3. Idle inventory state.

This prevents `No Disks` flicker and prevents zero mounted volumes from being
misrepresented as confirmed physical eject.

## 16. Swift 6.3.3 and strict compiler configuration — defect #5

### Package and platform configuration

For both `Package.swift` files:

- Change tools version to 6.3.
- Add a manifest compile guard requiring compiler 6.3.3 or newer:

```swift
#if !compiler(>=6.3.3)
#error("SafeEject requires Swift 6.3.3 or newer")
#endif
```

- Set `.macOS(.v26)`.
- Explicitly select Swift 6 language mode for repository-owned targets.
- Apply common strict settings to production, tool, and test targets as
  appropriate.

Required compiler posture:

```swift
let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
]
```

Also enable:

- `-require-explicit-sendable` for public SwiftDiskArbitration declarations.
- `-enable-actor-data-race-checks` for debug and test configurations.
- An explicit CI build with `-strict-concurrency=complete`, even though Swift 6
  mode already makes complete checking mandatory.
- Separate Thread Sanitizer and Address Sanitizer test jobs.

Do not add `-warn-concurrency` as if it provides stronger checking than Swift 6
mode; it is redundant. Do not enable default `MainActor` isolation for the
plugin target because the StreamDeck action protocol is delivered through the
framework's own actor/executor.

### Modern Swift features to use deliberately

- `actor` for the runtime coordinator and ordered renderer.
- `Synchronization.Mutex` for synchronous C callback registry state and event
  sequence allocation.
- `Sendable` value snapshots across every task/actor boundary.
- `ContinuousClock` and generic `Clock` test injection.
- `withTaskCancellationHandler` for async bridge cancellation.
- Swift 6.2+ `isolated deinit` for `DiskSession`, allowing `daSession` to remain
  actor-isolated rather than `nonisolated(unsafe)` solely for cleanup.
- `NonisolatedNonsendingByDefault` so nonisolated async functions remain on the
  caller's actor unless code explicitly requests concurrency.
- Exhaustive enums and pure reducers for valid state transitions.

Do not adopt a language feature merely because it is new:

- Swift 6.3 `@c` is not needed; DiskArbitration already imports the callback
  function types required by its C API.
- Default main-actor isolation conflicts with the StreamDeck callback boundary.
- `@concurrent` is unnecessary unless profiling proves specific CPU work should
  leave its caller's actor.
- Do not replace understandable synchronization with atomics; this state has
  multi-field invariants and belongs in `Mutex` or an actor.

### Strict memory-safety cleanup

The implementation must make the strict compiler probe pass without globally
disabling diagnostics. Address each current category:

- Replace raw retained callback objects with opaque token cookies.
- Centralize raw pointer conversion and C callbacks in the unsafe adapter.
- Wrap `DADiskGetBSDName` and C-string conversion in one audited helper that
  copies the string while the DiskArbitration-owned pointer is valid.
- Remove `DiskSession.daSession`'s `nonisolated(unsafe)` by using actor isolation
  and `isolated deinit`.
- Explicitly acknowledge unavoidable DiskArbitration session calls only inside
  the adapter/session ownership boundary.
- Replace `String(format:)` C-varargs formatting with Swift formatting APIs or
  structured OSLog interpolation.
- Inventory all remaining `@unchecked Sendable`, `nonisolated(unsafe)`,
  `UnsafePointer`, `UnsafeRawPointer`, and `Unmanaged` uses. Remove each one or
  attach a specific invariant explaining ownership, isolation, and lifetime.

### StreamDeck dependency boundary

- Keep `@preconcurrency import StreamDeck` only in edge files that actually
  import it.
- Pin the currently reviewed StreamDeckPlugin dependency revision instead of a
  floating `main` branch:
  `4ab9413d360a8a8657172914c4f98ba3f86743f3`.
- Do not pass repository target compiler flags into the dependency package.
- Treat the dependency's `PluginCommunication` actor as the transport boundary,
  but do not assume that `@preconcurrency` makes action classes `Sendable`.
- Runtime actor checks and Thread Sanitizer are required because compile-time
  checking cannot prove the dependency's missing annotations.

## 17. Public and internal API changes

### Preserve

- Existing `DiskOperationResult` fields and general result semantics.
- Existing `DiskError` and `DiskErrorCategory` cases.
- Existing `ejectAll` convenience call.
- Existing plugin/action UUIDs and property setting schema.
- Default safe, non-forced eject behavior.

### Add

- `DiskOperationStage`.
- `PhysicalDeviceID` or equivalent typed whole-device identity.
- `DeviceEjectEvent` and `DeviceEjectOutcome`.
- Progress-capable `ejectAll` overload.
- Internal absolute deadline and clock injection.
- Internal registry diagnostics for tests.
- Plugin state/event/effect/presentation value types.

### Clarify

- `.timeout` means SafeEject's wait ended without confirmation; it does not
  claim that macOS cancelled the underlying request.
- `.cancelled` means the Swift caller stopped waiting; it also cannot cancel
  the submitted DiskArbitration request.
- Eject success is not inferred from an empty mounted-volume list.

## 18. Expected file organization

The implementer may choose equivalent filenames, but keep responsibilities
separated. Do not grow `EjectAction.swift` or `CallbackBridge.swift` into new
god objects.

### SwiftDiskArbitration

- `DiskSession.swift`: actor ownership, public operations, grouping, and batch
  orchestration.
- `DiskError.swift`: existing typed error mapping.
- `DiskEjectProgress.swift`: device IDs, stages, progress events, and outcomes.
- `Internal/DiskOperationRegistry.swift`: token allocation and resume-once race.
- `Internal/DiskArbitrationUnsafeAdapter.swift`: raw pointer/C API boundary.
- `Internal/DiskOperationTiming.swift`: deadlines and clock-generic helpers.
- Reduce `Internal/CallbackBridge.swift` to orchestration or replace it with the
  focused internal components above.

### Plugin

- `Actions/EjectAction.swift`: thin nonisolated protocol edge only.
- `EjectState.swift`: domain state/event/effect/presentation values.
- `EjectReducer.swift`: pure transition and presentation rules.
- `EjectCoordinator.swift`: ordered actor runtime and effect execution.
- `EventIngress.swift`: synchronous sequenced event submission.
- `DiskCountMonitor.swift`: inventory source and main-actor system resources.
- `StreamDeckRenderer.swift`: ordered context-scoped transport.

### Tests

- Add focused registry, timing, progress, reducer, coordinator, lifecycle,
  monitor, and renderer test files rather than overloading existing suites.

## 19. Implementation sequence

Keep the branch buildable after each major step. Do not combine every change
into one unreviewable commit.

### Phase 0 — preserve baseline

1. Confirm clean worktree and branch.
2. Record `swift --version`, `sw_vers`, dependency revision, and baseline tests.
3. Run both existing test suites.
4. Run the current release build and Stream Deck structural validation.
5. Do not edit release metadata yet.

### Phase 1 — enable Swift 6 language checking

1. Upgrade package tools to 6.3 and target macOS 26.
2. Enable Swift 6 language mode and `NonisolatedNonsendingByDefault` for owned
   targets.
3. Keep StreamDeck behind `@preconcurrency` and pin its revision.
4. Resolve owned-code concurrency diagnostics without adding broad unchecked
   conformances.
5. Keep strict memory safety temporarily as an explicit failing audit command
   until Phase 2 isolates the C boundary.

### Phase 2 — callback registry and monotonic timing

1. Add manual-clock and registry tests first.
2. Implement opaque token registry and C adapter.
3. Add cancellation arbitration.
4. Replace `Date` timing with `ContinuousClock`.
5. Enforce 25-second unmount and 30-second overall absolute deadlines.
6. Enable strict memory safety and warnings-as-errors permanently.
7. Remove/justify every remaining unsafe diagnostic.
8. Run library tests plus ASan and TSan before proceeding.

### Phase 3 — progress API and device outcomes

1. Add stage/device/progress value types.
2. Refactor physical-device task group to emit progress immediately.
3. Preserve the no-progress public overload.
4. Add mixed-device and fast-failure tests.
5. Confirm physical-device grouping still ejects multipartition disks once.

### Phase 4 — pure state machine

1. Add state/event/effect/presentation enums.
2. Implement the pure reducer with exhaustive transitions.
3. Add parameterized event-trace tests before connecting Stream Deck.
4. Prove the safety invariant: only eject success reaches `safeToRemove`.
5. Prove zero inventory cannot override an active or unconfirmed operation.

### Phase 5 — coordinator and action lifecycle

1. Add sequenced event ingress and one consumer.
2. Add coordinator actor and effect execution.
3. Thin `EjectAction` to immutable value-event submission.
4. Add subscription IDs, action-instance IDs, generations, and render revisions.
5. Add renderer actor and context-scoped stale-command rejection.
6. Delete the old mutable action properties and global unchecked eject state.
7. Run actor-data-race checks and TSan lifecycle tests.

### Phase 6 — monitor and first paint

1. Replace `lastCount` with `DiskInventoryState`.
2. Implement `Checking…` first paint and unavailable failure.
3. Invalidate cache and refresh generations after final unsubscribe.
4. Add wake refresh and retain subscriber-only 30-second fallback.
5. Route inventory through the coordinator so it cannot overwrite operation
   presentation.
6. Test rapid lifecycle and multiple keys.

### Phase 7 — release and compatibility migration

1. Change plugin version to `4.0.0.0` and macOS requirement to 26.
2. Rename `docs/RELEASE_NOTES_v3.0.4.md` to the 4.0.0 release note.
3. Correct timeout, idle CPU, safety, and compatibility wording.
4. Update repository and library READMEs.
5. Move CI to `macos-26`, pin Swift 6.3.3, and add independent library tests
   and sanitizer jobs.
6. Validate/export/package without mutating the live Stream Deck installation.
7. Install on the physical Stream Deck only for final UAT.

## 20. Detailed automated test plan

Tests use Swift Testing. Keep test state isolated so tests remain parallel-safe.
Use `#expect` by default, `#require` for prerequisites, parameterized tests for
event matrices, and `confirmation` for callback delivery counts. Do not use
sleep as the primary synchronization mechanism.

### Callback registry tests

- Callback wins before deadline and returns the DiskArbitration result.
- Timeout wins and returns `.timeout`.
- Cancellation wins and returns `.cancelled`.
- Callback and timeout race; exactly one continuation resumes.
- Callback and cancellation race; exactly one continuation resumes.
- Timeout and cancellation race; exactly one continuation resumes.
- A late callback after timeout is ignored safely.
- A duplicate callback is ignored safely.
- A callback with an unknown token is ignored safely.
- Nil C context is handled without crash.
- Repeated never-callback operations leave pending count at zero.
- Thousands of randomized races leave pending count at zero.
- Token zero is never allocated.
- Token rollover skips active tokens without collision.
- Continuations are always resumed outside the mutex; include a re-entrant test
  that would deadlock if resumed under lock.

### Deadline tests

- Standalone unmount uses a monotonic 30-second absolute deadline.
- Combined unmount starts at zero with deadlines at 25 and 30 seconds.
- Busy at 100 ms finishes immediately.
- Permission error at 100 ms finishes immediately.
- Unmount success at 2 seconds starts eject with 28 seconds remaining.
- Unmount success at 24 seconds starts eject with 6 seconds remaining.
- Unmount pending at 25 seconds returns unmount timeout and does not start
  eject.
- Eject pending at the overall 30-second deadline returns eject timeout.
- A callback submitted before an exact deadline wins when the test orders it
  first; deadline wins when ordered first.
- Simulated wall-clock changes have no effect because production logic never
  reads `Date`.
- Reported durations derive from the monotonic clock.

### Progress and batch tests

- Progress stage order is unmount started, unmount completed, eject started,
  completed.
- A dissenter skips subsequent stages.
- Three physical devices execute independently.
- A fast busy device publishes before a slow device finishes.
- Multiple partitions on one device produce one physical workflow.
- Partial success preserves each device result.
- The compatibility overload returns the same final result as the progress
  overload.

### Reducer state tests

- Initial appearance transitions from inactive to checking.
- Fresh inventory transitions checking to ready.
- Session failure transitions checking to unavailable presentation.
- Key release starts one operation.
- A second key release cannot start a duplicate active operation.
- Long press remains ignored.
- Unmount progress updates only the matching operation/device.
- Unmount success transitions to unmounted/ejecting, not safe.
- Eject success is the only transition to `safeToRemove`.
- Disappearance without eject confirmation is not safe.
- Busy failure renders immediately.
- Timeout never renders success.
- Zero inventory during eject does not change operation presentation.
- Mixed safe/failed devices produce partial failure.
- Stale operation events are ignored.
- Settings changes alter title visibility without changing operation state.
- Completion followed by a new operation rejects old events.

### Timing presentation tests

- Pending stage before 3 seconds maps to normal `Ejecting…`.
- At 3 seconds it maps to `Working…`.
- At 15 seconds it maps to `Check Disk`.
- A definitive `In Use` result overrides slow/attention presentation
  immediately.
- Successful completion maps to `Ejected!` only after eject confirmation.

### Lifecycle and renderer tests

- Appear registers exactly one subscription.
- Duplicate appearance replaces or ignores safely without duplicate observers.
- Disappear removes exactly the matching subscription.
- Old disappear cannot remove a newer instance for the same context.
- Refresh completion after disappearance cannot render.
- Settings completion after disappearance cannot render.
- Old render revision cannot overwrite a newer revision.
- Multiple contexts receive no cross-talk.
- Last subscriber stops resources exactly once.
- Start/stop epoch inversion cannot resurrect monitoring.
- Renderer commands remain ordered for one context.

### Inventory tests

- First appearance publishes `.checking`, never zero.
- `Checking…` respects `showTitle` false.
- Fresh zero renders `No Disks` only in idle inventory state.
- Fresh positive counts pluralize correctly.
- A second subscriber while active may receive the valid cached value.
- Final unsubscribe invalidates cache.
- A new subscriber after idle receives checking even if the previous cached
  value was nonzero.
- Session unavailability renders failed, not no disks.
- Newer refresh generation wins over an older result.
- Mount, unmount, rename, wake, fallback, and explicit refresh all request a
  refresh.
- No observer/timer remains after the final subscriber leaves.

### Privacy tests

- Structured logs contain counts, resolved BSD layer order, stage, target,
  category, raw status, duration, and operation ID only where allowed.
- Terminal success summaries use OSLog notice; failures, timeouts, and
  cancellations use OSLog error so multi-day support investigations do not
  depend on short-lived info records.
- Logs never contain volume name or path from synthetic sensitive test data.
- Future diagnostic fields are not serialized or logged accidentally.

## 21. Compiler and CI validation matrix

Use independent commands so one package's tests do not masquerade as coverage
for the other package's test target.

### Required local/CI commands

From `swift/Packages/SwiftDiskArbitration`:

```sh
swift test
swift test --sanitize=address
swift test --sanitize=thread
```

Add an explicit strict audit equivalent to:

```sh
swift test \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -strict-memory-safety \
  -Xswiftc -require-explicit-sendable \
  -Xswiftc -warnings-as-errors
```

From `swift-plugin`:

```sh
swift test
swift test --sanitize=thread
swift build -c release
```

Then run:

```sh
streamdeck-swift-builder inspect --repo <repo> --json
streamdeck-swift-builder export-manifest \
  --repo <repo> \
  --output <temporary-directory> \
  --validate \
  --pack-dry-run \
  --pack-output <temporary-directory>
```

If the CLI is not installed globally, use the bundled skill CLI with
`swift run --package-path ...` as described by the Stream Deck builder skill.

### CI structure

- Runner: `macos-26`.
- Swift setup: exactly 6.3.3.
- Job 1: library strict build and tests.
- Job 2: plugin tests and release build.
- Job 3: Address Sanitizer library tests.
- Job 4: Thread Sanitizer library/plugin concurrency tests.
- Job 5: export, official Stream Deck validation, pack dry run, and artifact
  upload.
- Do not upload/publish a release from a failing or partially skipped matrix.

## 22. Physical Stream Deck and disk UAT

DiskArbitration is not currently recorded in the shared Stream Deck default-host
capability matrix. Existing real use is encouraging but 4.0.0 changes the OS,
compiler, callback bridge, and lifecycle. Revalidate it on the actual raw
executable host.

### Devices and scenarios

- Single-volume USB flash drive.
- Multipartition USB device.
- External SSD.
- Slow mechanical HDD.
- SD card and card reader.
- APFS, HFS+, and ExFAT where hardware is available.
- Multiple physical devices simultaneously.
- Disk image for deterministic nonphysical coverage, without treating it as a
  substitute for removable hardware.

### Behavior scenarios

- Normal fast eject.
- An application holding an open document on the disk.
- Spotlight actively indexing.
- Active copy/write operation.
- Time Machine-style disk activity if available.
- Missing Full Disk Access.
- Device removed unexpectedly during each stage.
- Sleep/wake with a visible key.
- Stream Deck profile switch during enumeration and ejection.
- Rapid key appearance/disappearance.
- Multiple SafeEject keys on one or more Stream Deck devices.
- Repeated key presses while one operation is active.
- Stream Deck restart during an operation.

### What to observe

- Known failures appear immediately.
- 3-second and 15-second messages appear at the intended thresholds.
- No false `Ejected!` appears after unmount-only success, timeout, or unexpected
  disappearance.
- All-success operations produce `Ejected!` only after eject callbacks succeed.
- A busy disk does not hide successful progress for other physical devices.
- No vanished action context receives display writes.
- Counts recover after late OS changes, wake, and profile changes.
- OSLog contains no private volume or path data.

### Memory/concurrency instruments

- Run Instruments Allocations and Leaks while repeatedly exercising successful,
  busy, timeout-simulated, cancelled, and late-callback paths.
- Pending registry entry count must return to zero after every terminal path.
- Run a Thread Sanitizer build under the real Stream Deck host if practical.
- Verify the plugin process remains alive and responsive after each adversarial
  scenario.

## 23. Release migration and documentation

### Version and compatibility

- Change code/manifest version from `3.0.4.0` to `4.0.0.0`.
- Release/tag name: `v4.0.0`.
- Minimum macOS: 26 everywhere.
- Required development toolchain: Swift 6.3.3 or newer.
- Minimum Stream Deck remains 6.9 unless separate validation finds a reason to
  change it.

### Documentation updates

- Rename release notes to `docs/RELEASE_NOTES_v4.0.0.md`.
- State prominently that macOS 13–15 are no longer supported.
- Explain that 30 seconds is an exceptional hard watchdog, not the expected
  wait for a busy disk.
- Explain progressive 3/15-second feedback.
- Explain that known macOS errors are shown as soon as returned.
- Do not claim literal zero idle CPU; describe event-driven monitoring plus the
  subscriber-only 30-second fallback.
- Update the top-level README and SwiftDiskArbitration README requirements.
- Keep Full Disk Access setup documentation aligned; no new permission should be
  introduced by this plan.
- Do not advertise blocker-process identification in 4.0.0.

### Release gate

Do not tag, package for distribution, or publish 4.0.0 until:

- Every automated matrix job passes.
- Strict memory safety passes with no unreviewed unsafe suppressions.
- TSan and actor runtime checks report no owned-code violations.
- Instruments shows no growth from repeated missing/late callbacks.
- Physical UAT passes on the normal Stream Deck executable host.
- The final packaged plugin advertises 4.0.0.0 and macOS 26.
- Release notes accurately distinguish confirmed success, definitive failure,
  and indeterminate timeout.

## 24. Prohibited shortcuts and common failure modes

The implementation agent must not:

- Release the retained callback object from the timeout path; a late callback
  would then be a use-after-free.
- Keep `passRetained` and merely accept a small leak.
- Resume a continuation while holding a lock.
- Use `Date` for durations or deadlines.
- Restart a relative timeout at each stage.
- Treat timeout as cancellation of DiskArbitration.
- Treat volume count zero as physical eject confirmation.
- Treat an unexpected disappearance as safe eject success.
- Delay a known busy/permission error until a UX threshold.
- Run a blocker preflight before the actual unmount.
- Capture `EjectAction` in an escaping task.
- Assume independent `Task` blocks preserve lifecycle order.
- Add `@unchecked Sendable` merely to satisfy the compiler.
- Use `@preconcurrency` on repository-owned modules.
- Mark the whole plugin `@MainActor` to silence StreamDeck protocol issues.
- Force Swift 6 flags into the Swift 5 StreamDeck dependency.
- Use test sleeps to make races appear deterministic.
- Serialize the entire test suite instead of isolating test state.
- Log volume names, paths, or future blocker details.
- Change UUIDs or add app-bundle/signing/entitlement work.
- Implement PID/app blocker detection in this release.

## 25. Final acceptance checklist

### Defect #1 — leak-free bridge

- [x] No retained Swift object is passed as C callback context.
- [x] Token registry winner resumes exactly once.
- [x] Timeout, cancellation, duplicate, and late callbacks are safe.
- [x] Pending registry count returns to zero.
- [x] Strict memory safety passes at the C boundary.
- [ ] Instruments finds no callback-path leak.

### Defect #2 — strict monotonic deadline

- [x] All relevant timing uses `ContinuousClock`.
- [x] Absolute unmount deadline is start + 25 seconds.
- [x] Absolute overall deadline is start + 30 seconds.
- [x] No stage extends the overall budget.
- [x] Known failures publish immediately.
- [x] 3/15-second progressive events are deterministic.
- [x] Manual-clock tests cover all boundaries.

### Defect #3 — race-free lifecycle

- [x] Action edge has no mutable cross-executor business state.
- [x] No async task captures an action instance.
- [x] Events have one explicit submission order.
- [x] Subscription IDs and action tokens reject stale lifecycle work.
- [x] Coordinator actor owns the state machine.
- [x] Renderer rejects stale contexts/revisions.
- [x] Final subscriber tears down all monitoring resources.
- [x] TSan and actor runtime checks pass.

### Defect #4 — fresh first paint

- [x] First idle-to-visible transition renders checking, not zero.
- [x] Only a fresh enumeration renders a count.
- [x] Idle monitor cache is invalidated.
- [x] Session failure renders failed.
- [x] Wake and fallback refresh are present.
- [x] Inventory cannot overwrite operation presentation.
- [x] Release notes no longer claim zero idle CPU.

### Swift 6.3.3 / macOS 26 / release

- [x] Both packages require tools 6.3 and compiler 6.3.3.
- [x] Both packages explicitly use Swift 6 language mode.
- [x] Minimum platform is macOS 26 everywhere.
- [x] Strict memory safety and warnings-as-errors are permanent.
- [x] Public Sendable annotations are explicit.
- [x] `isolated deinit` removes the session cleanup escape hatch.
- [x] StreamDeck dependency is pinned and isolated behind `@preconcurrency`.
- [x] CI is configured for macOS 26 with Swift 6.3.3.
- [x] Plugin and packaged manifest versions are 4.0.0.0.
- [ ] Tag/release `v4.0.0` is created only after physical UAT approval.
- [x] Official validation, pack dry run, and isolated real packaging pass.

### State machine and safety

- [x] State/event/effect/presentation types are enums/value types.
- [x] Reducer has exhaustive deterministic tests.
- [x] Only eject callback success reaches `safeToRemove`.
- [x] APFS whole-media ancestry resolves and is ordered inner-to-outer.
- [x] Multiple synthesized branches on one physical device are deduplicated
  without racing the final physical eject.
- [x] Every copied IOKit media, parent, and iterator handle is released.
- [x] Ambiguous or unavailable physical ancestry fails closed.
- [x] A no-disk key press is neutral and cannot request green feedback.
- [x] Busy errors surface immediately.
- [x] BSD-wrapped `unix_err(EBUSY)` maps to the typed busy category.
- [x] Mixed-device outcomes cannot produce overall success.
- [x] Failure retains device, stage, category, and raw status for future work.
- [x] No PID/app scanning or blocker UI was added.

## 26. Copy-ready continuation prompt for a lesser model

Use the following prompt in a future session:

> Work in `/Users/deverman/Documents/code/streamdeck/eject_all_disks_streamdeck`
> on branch `eject-reliability-instant-counts`. Read `AGENTS.md` and then read
> `docs/SAFE_EJECT_4_0_0_CORRECTNESS_PLAN.md` completely before editing. Treat
> that document as the implementation contract. Preserve unrelated user
> changes and keep the worktree buildable after each phase.
>
> The APFS inner-to-outer correction is implemented, installed, and approved by
> replacement UAT. Audit the current diff, confirm the installed binary still
> matches the release build, and continue with the merge and release workflow.
> Preserve the UAT evidence showing successful eject callbacks for the
> synthesized APFS whole disk and then the physical USB whole disk.
>
> Preserve the callback registry, monotonic deadlines, per-device progress,
> enum-driven reducer, ordered event ingress, lifecycle tokens, fresh first
> paint, and strict compiler settings.
> Do not infer eject success from a zero mounted-volume count or a disappearance
> callback; only a successful `DADiskEject` callback reaches `safeToRemove`.
> Known dissenters must publish immediately. Use the 3-second slow, 15-second
> attention, 25-second unmount, and 30-second overall thresholds.
>
> Keep blocker-process detection out of scope. Preserve only typed failure
> context for a later feature. Do not add force eject, automatic retries, new
> UI, an app bundle, UUID changes, or private logging.
>
> Use Swift 6.3.3, Swift 6 language mode, macOS 26,
> `NonisolatedNonsendingByDefault`, strict memory safety, warnings-as-errors,
> explicit Sendable checking, debug actor data-race checks, ASan, and TSan.
> Keep `@preconcurrency import StreamDeck` only at the third-party edge and do
> not use unchecked annotations to silence repository-owned races.
>
> Add deterministic Swift Testing coverage with manual clocks and controlled
> callbacks; never use sleeps to prove correctness. Run both package test suites
> independently and report every validation command and any skipped physical
> UAT. Do not tag, push, or publish without explicit approval.
