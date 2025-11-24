# Optimization: Event-Driven Disk Monitoring

## Goal
Replace the 3-second polling interval with event-driven disk monitoring for instant UI updates when disks are mounted/unmounted.

## Current Behavior
In `eject-all-disks.ts`:
```typescript
// Check disk count every 3 seconds
const interval = setInterval(async () => {
  await this.updateDiskCount(action);
}, 3000);
```

This means:
- Up to 3 second delay before badge updates
- Continuous CPU usage even when no changes
- Multiple concurrent polling timers (one per visible action)

## Proposed Architecture

### Option A: DiskArbitration Notifications (Swift-side)
1. Create a long-running Swift process that watches for disk events
2. Use `DARegisterDiskAppearedCallback` and `DARegisterDiskDisappearedCallback`
3. Communicate changes to the Node.js plugin via:
   - Named pipe / Unix socket
   - File-based signaling
   - Stdout streaming

### Option B: FSEvents (Swift-side)
1. Watch `/Volumes` directory for changes using FSEvents
2. Trigger count update when directory contents change
3. Same communication options as Option A

### Option C: Node.js fs.watch (TypeScript-side)
1. Use `fs.watch('/Volumes')` to detect mount changes
2. Debounce rapid changes
3. Update disk count on change event

## Recommended Approach: Option C
Simplest to implement, no Swift changes needed.

```typescript
import { watch } from 'fs';

// In startMonitoring():
const watcher = watch('/Volumes', { persistent: false }, (eventType, filename) => {
  // Debounce and update count
  this.debouncedUpdateDiskCount(action);
});
```

## Files to Modify
- `src/actions/eject-all-disks.ts`

## Challenges
1. `fs.watch` reliability varies by platform (but we only target macOS)
2. Need to handle rapid mount/unmount events (debouncing)
3. Watcher cleanup on action disappear
4. May still want a slow fallback poll (30s) for edge cases

## Expected Improvement
- Instant badge updates (sub-100ms vs 3000ms)
- Reduced CPU usage when idle
- Better user experience

## Testing
1. Mount a USB drive - badge should appear instantly
2. Eject via Finder - badge should disappear instantly
3. Rapid mount/unmount - should handle gracefully
4. Multiple Stream Deck buttons - should all update together
