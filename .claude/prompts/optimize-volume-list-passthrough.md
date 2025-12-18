# Optimization: Volume List Passthrough

## Goal

Eliminate redundant volume enumeration by passing the volume list from the TypeScript plugin to the Swift binary.

## Current Behavior

1. TypeScript plugin calls `eject-disks list` to get volumes (for count display)
2. User presses button
3. TypeScript calls `eject-disks eject`
4. Swift binary enumerates volumes AGAIN internally
5. Swift performs ejection

This means volumes are enumerated twice - once in step 1 and again in step 4.

## Proposed Change

Add a `--volumes` flag to accept a comma-separated list of BSD names:

```bash
# Current
./eject-disks eject --verbose

# Proposed
./eject-disks eject --verbose --volumes "disk2s1,disk3s1,disk4s1"
```

When `--volumes` is provided:

- Skip enumeration
- Use provided BSD names directly
- Create DADisk references from BSD names

## Files to Modify

- `swift/Sources/EjectDisks.swift` - Add `--volumes` option to Eject command
- `src/actions/eject-all-disks.ts` - Pass volume BSD names when calling eject

## Implementation Details

### Swift side:

```swift
struct Eject: AsyncParsableCommand {
  @Option(name: .long, help: "Comma-separated BSD names to eject")
  var volumes: String?

  func run() async {
    if let volumeList = volumes {
      // Parse and use provided volumes
      let bsdNames = volumeList.split(separator: ",").map(String.init)
      output = await ejectSpecificVolumes(bsdNames: bsdNames, ...)
    } else {
      // Existing behavior - enumerate and eject
      output = await ejectAllVolumesNative(...)
    }
  }
}
```

### TypeScript side:

```typescript
// Cache the volume list from monitoring
private cachedVolumes: VolumeInfo[] = [];

// In onKeyDown:
const bsdNames = this.cachedVolumes.map(v => v.bsdName).join(',');
const ejectCommand = `sudo -n "${binaryPath}" eject --verbose --volumes "${bsdNames}"`;
```

## Expected Improvement

- Save ~50-100ms on enumeration
- More consistent behavior (eject exactly what was displayed)
- Avoid race conditions where disks change between display and eject

## Risk Assessment

- MEDIUM - need to handle edge cases:
    - Volume unmounted between display and eject
    - Invalid BSD name passed
    - Empty volume list

## Testing

1. Mount disks, verify count shows correctly
2. Press eject with --volumes flag
3. Verify correct disks are ejected
4. Test with stale BSD names (already ejected disk)
