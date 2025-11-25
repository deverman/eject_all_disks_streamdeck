# Optimization: Async Blocking Process Detection

## Goal
Run blocking process detection (`lsof`) in parallel with the next disk ejection instead of sequentially.

## Current Behavior
In `EjectDisks.swift`, when ejection fails with verbose mode:
```swift
for singleResult in batchResult.results {
  if !singleResult.success && verbose {
    let processes = getBlockingProcesses(path: singleResult.volumePath)  // BLOCKING
    blockingProcesses = processes.isEmpty ? nil : processes
  }
  // ... build result
}
```

`getBlockingProcesses()` runs `lsof` synchronously, which can take 1-5 seconds per volume.

## Proposed Change
1. Collect all failed volumes first
2. Run `lsof` for all failed volumes in parallel using Swift concurrency
3. Match results back to the failure reports

```swift
// Collect failures
let failedVolumes = batchResult.results.filter { !$0.success }

// Run lsof in parallel for all failures
let blockingProcessesMap = await withTaskGroup(of: (String, [ProcessInfoOutput]).self) { group in
  for result in failedVolumes {
    group.addTask {
      let processes = getBlockingProcesses(path: result.volumePath)
      return (result.volumePath, processes)
    }
  }
  // Collect results into dictionary
  var map: [String: [ProcessInfoOutput]] = [:]
  for await (path, processes) in group {
    map[path] = processes
  }
  return map
}
```

## Files to Modify
- `swift/Sources/EjectDisks.swift` - `ejectAllVolumesNative()` function

## Key Code Location
Around line 191-212 in EjectDisks.swift where results are processed.

## Expected Improvement
- If 3 disks fail, lsof runs 3x in parallel instead of sequentially
- Saves 2-10 seconds on multi-disk failures
- No impact on success path (lsof only runs on failures)

## Risk Assessment
- LOW risk - only affects diagnostic output
- lsof is read-only, safe to parallelize
- Worst case: slightly delayed error reporting

## Testing
1. Open files on multiple disks to force ejection failures
2. Run `./eject-disks eject --verbose`
3. Measure total time vs sequential approach
