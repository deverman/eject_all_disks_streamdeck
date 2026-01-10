# Benchmark Plan: Old vs New Plugin Architecture

## Objective

Compare the performance of:
- **Old Version**: TypeScript/Node.js plugin + Swift CLI tool (`eject-disks`)
- **New Version**: Pure Swift Stream Deck plugin using StreamDeckPlugin library

## Background

The old architecture had:
- Node.js plugin handling Stream Deck communication
- Shell script spawning Swift CLI binary for disk operations
- Multiple process boundaries and IPC overhead

The new architecture has:
- Single Swift binary handling everything
- Direct DiskArbitration framework calls
- No subprocess spawning

## Benchmark Strategy

### Phase 1: Restore Old Version for Testing

```bash
# Checkout the last commit before Swift-native refactor
git log --oneline | grep -i "node\|typescript\|cli" | head -5

# Create a branch for benchmarking
git checkout -b benchmark-comparison <old-commit-hash>

# Build old version
# (depends on old build system - likely npm install + swift build)
```

### Phase 2: Create Benchmark Harness

Create a benchmark script that:
1. Mounts a test disk image (to have consistent test data)
2. Measures time from button press to eject completion
3. Runs multiple iterations (10+) for statistical significance
4. Records: total time, disk enumeration time, eject time

```bash
#!/bin/bash
# benchmark-compare.sh

ITERATIONS=10
TEST_DMG="test-benchmark.dmg"

# Create test disk image
hdiutil create -size 100m -fs HFS+ -volname "BenchmarkDisk" $TEST_DMG

for i in $(seq 1 $ITERATIONS); do
    # Mount
    hdiutil attach $TEST_DMG -quiet
    sleep 1  # Let system settle

    # Time the eject (OLD VERSION)
    OLD_START=$(gdate +%s.%N)
    # ... invoke old plugin eject ...
    OLD_END=$(gdate +%s.%N)

    # Remount for new version test
    hdiutil attach $TEST_DMG -quiet
    sleep 1

    # Time the eject (NEW VERSION)
    NEW_START=$(gdate +%s.%N)
    # ... invoke new plugin eject ...
    NEW_END=$(gdate +%s.%N)

    echo "Iteration $i: Old=$(OLD_END-OLD_START)s, New=$(NEW_END-NEW_START)s"
done
```

### Phase 3: Metrics to Capture

| Metric | Description | How to Measure |
|--------|-------------|----------------|
| **Total Eject Time** | Button press to completion | Timer in benchmark script |
| **Enumeration Time** | Time to find ejectable volumes | Add timing logs to code |
| **Per-Volume Eject** | Time for each volume to unmount | Already tracked in BatchEjectResult |
| **Memory Usage** | Peak memory during operation | `time -l` or Instruments |
| **CPU Usage** | CPU time consumed | `time` command |

### Phase 4: Test Scenarios

1. **Single USB Drive** - Most common case
2. **Multiple USB Drives (3+)** - Tests parallel eject
3. **Disk Image** - Tests .dmg handling
4. **Large Drive (1TB+)** - Tests with many files
5. **Drive with Open Files** - Tests busy handling (will fail, but timing matters)

### Phase 5: Add Retry Logic (Bug #2) After Baseline

Once baseline benchmarks are complete:

1. Implement retry logic for busy disks in `DiskSession.swift`:
```swift
// In ejectPhysicalDevice():
var retryCount = 0
let maxRetries = 3
var lastResult: DiskOperationResult

repeat {
    lastResult = await unmountDiskAsync(...)
    if lastResult.success { break }

    // Only retry on busy errors
    guard lastResult.error?.isDiskBusy == true else { break }

    retryCount += 1
    let delay = pow(2.0, Double(retryCount)) * 0.1  // 100ms, 200ms, 400ms
    try? await Task.sleep(for: .seconds(delay))
} while retryCount < maxRetries
```

2. Re-run benchmarks to measure retry overhead
3. Compare: baseline vs retry-enabled

### Expected Results

Based on architectural analysis:
- **Enumeration**: New should be ~same (both use DiskArbitration)
- **Eject Initiation**: New should be faster (no subprocess spawn)
- **Total Time**: New should be 10-50% faster for single disk
- **Multiple Disks**: New should be significantly faster (true parallelism)

## Implementation Notes

### Invoking Old Plugin from Command Line

The old Swift CLI can be invoked directly:
```bash
./org.deverman.ejectalldisks.sdPlugin/bin/eject-disks eject-all
```

### Invoking New Plugin from Command Line

The new plugin is designed for Stream Deck, but we can test the library directly:
```swift
// Create test file: swift-plugin/Sources/Benchmark/main.swift
import SwiftDiskArbitration

let session = try DiskSession()
let start = Date()
let volumes = await session.enumerateEjectableVolumes()
let enumTime = Date().timeIntervalSince(start)

let ejectStart = Date()
let result = await session.ejectAll(volumes)
let ejectTime = Date().timeIntervalSince(ejectStart)

print("Enumeration: \(enumTime)s")
print("Eject: \(ejectTime)s")
print("Total: \(enumTime + ejectTime)s")
```

## Timeline

1. **Day 1**: Restore old version, create test disk images
2. **Day 2**: Create benchmark harness, run baseline tests
3. **Day 3**: Implement retry logic, run comparison tests
4. **Day 4**: Analyze results, document findings

## Success Criteria

- New version should be at least as fast as old version
- Retry logic should add minimal overhead (<50ms for non-retry cases)
- Memory usage should be comparable or lower

---

## AI Prompt for Implementation

When ready to implement this benchmark, use the following prompt:

```
I need to benchmark the Stream Deck Eject All Disks plugin.

Context:
- The project is at: /Users/deverman/Documents/Code/firststreamdeck/eject_all_disks_streamdeck
- Current branch has the new Swift-native implementation
- Old version used TypeScript + Swift CLI (see git history)
- Benchmark files were previously in benchmark/ directory (deleted)

Tasks:
1. Find the last commit with the old TypeScript/CLI implementation
2. Create a benchmark script that:
   - Mounts a test disk image
   - Times the eject operation for both versions
   - Runs 10 iterations and calculates mean/stddev
3. Run the benchmark and report results
4. If new version is faster, implement retry logic (Bug #2 from security review)
5. Re-benchmark with retry logic to measure overhead

Report results in a markdown table comparing:
- Total time (mean, stddev, min, max)
- Memory usage
- Success rate
```
