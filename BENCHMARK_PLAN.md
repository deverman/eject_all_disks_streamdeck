# Benchmark Plan: Legacy CLI vs Current Swift Implementation

## Goal

Benchmark the current Swift-native implementation against the legacy command-line tool (historical `eject-disks`) by building both from git history and running repeatable scenarios.

## Approach (use worktrees)

Build and run both versions side-by-side without constantly switching branches:

```bash
# Pick a legacy commit that still contains the CLI (before it was removed).
git log --oneline | rg -n "remove Node\\.js, CLI|Simplify plugin" -n
git log --oneline --all | rg -n "eject-disks|CLI tool" -n

git worktree add ../eject-bench-legacy <legacy-commit-hash>
git worktree add ../eject-bench-current HEAD
```

## Build

### Current (library harness)

The current checkout includes a benchmark harness executable under `swift/Packages/SwiftDiskArbitration`.

```bash
cd ../eject-bench-current/swift/Packages/SwiftDiskArbitration
swift run -c release swiftdiskarb-bench --help
```

### Legacy (CLI)

From the legacy worktree, locate and build the CLI:

```bash
cd ../eject-bench-legacy
rg -n "eject-disks|EjectDisks" -S .
swift build -c release
```

If the CLI is in a sub-package, `cd` into that folder and run `swift build -c release` there.

## Make the test repeatable (recommended)

Use a DMG so you don’t repeatedly eject real hardware:

```bash
hdiutil create -size 100m -fs HFS+ -volname "BenchmarkDisk" test-benchmark.dmg
hdiutil attach test-benchmark.dmg -quiet
```

## What to measure

- Enumeration time (counting / listing ejectable volumes)
- Eject time (unmount + physical eject)
- Success rate
- CPU/memory (`/usr/bin/time -l …` on macOS)

## Suggested runs

Current enumeration only (safe):

```bash
cd ../eject-bench-current/swift/Packages/SwiftDiskArbitration
swift run -c release swiftdiskarb-bench enumerate --iterations 50
```

Current eject benchmark (requires explicit confirmation flag):

```bash
swift run -c release swiftdiskarb-bench eject --iterations 10 --confirm-eject YES
```

Legacy eject (example; exact path depends on the legacy package):

```bash
cd ../eject-bench-legacy
./.build/release/eject-disks eject-all
```

## Optional: Retry experiments (after baseline)

If you add retries, only retry on busy/exclusive-access errors, then re-run the same scenarios and compare the non-retry overhead.
