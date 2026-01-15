# Product Requirements Document
## Smart Pre-Ejection Blocker Termination

**Version:** 2.0
**Date:** 2026-01-11
**Status:** Future Feature - Not Yet Implemented
**Author:** Claude
**Architecture:** Swift-native (StreamDeckPlugin library)

---

## Executive Summary

Design and implement an intelligent blocker termination system that automatically handles processes blocking disk ejection, improving success rate from ~60% to >95%.

### Key Features

| Feature | Description |
|---------|-------------|
| **Native Detection** | Use `libproc` APIs for ~50ms blocker detection |
| **Smart Classification** | Categorize processes as safe/unsafe to terminate |
| **Graceful Cascade** | Pause → Graceful quit → Force kill strategy |
| **User Control** | Per-process policies via Property Inspector |
| **Auto Recovery** | Resume paused processes after ejection |

### Success Metrics

- **Speed:** <100ms overhead when no blockers present
- **Effectiveness:** >95% first-attempt success rate
- **Safety:** Zero data loss incidents

---

## Problem Statement

### Current Behavior

When a process has files open on an external disk, ejection fails with an error like "In Use". Users must manually:
1. Identify which process is blocking
2. Close the blocking application
3. Retry ejection

### Common Blockers

| Process | Description | Safe to Terminate? |
|---------|-------------|-------------------|
| `mds`, `mds_stores` | Spotlight indexing | Yes (auto-restarts) |
| `photoanalysisd` | Photos analysis | Yes (can pause) |
| `bird`, `cloudd` | iCloud sync | Yes (can pause) |
| `backupd` | Time Machine | Yes (can pause) |
| Music, Photos, Preview | User apps | Ask user |
| IDEs (Xcode, VS Code) | Developer tools | Warn (unsaved work) |

---

## Technical Architecture

### Integration Point

The feature integrates into `DiskSession.swift` in the `ejectAll()` method:

```swift
// swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/DiskSession.swift

public func ejectAll(_ volumes: [Volume], options: EjectOptions) async -> BatchEjectResult {
    // 1. Try fast ejection first
    let result = await attemptEjection(volumes)

    if result.allSucceeded {
        return result  // Fast path: no blockers
    }

    // 2. NEW: Detect and handle blockers
    if options.handleBlockers {
        let blockers = await detectBlockers(for: result.failedVolumes)
        let plan = buildTerminationPlan(blockers, policy: options.blockerPolicy)

        if plan.requiresUserConfirmation {
            // Signal to UI layer for confirmation
            // (via callback or async stream)
        }

        await executePlan(plan)

        // 3. Retry ejection
        let retryResult = await attemptEjection(result.failedVolumes)

        // 4. Recover terminated processes
        await recoverProcesses(plan.terminatedProcesses)

        return retryResult
    }

    return result
}
```

### New Components

#### 1. BlockerDetector

```swift
// swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/BlockerDetector.swift

import Darwin

public struct BlockingProcess: Sendable {
    public let pid: pid_t
    public let name: String
    public let category: ProcessCategory
    public let fileHandles: [FileHandle]
}

public enum ProcessCategory: Sendable {
    case systemServiceSafe       // Spotlight, Photos analysis - auto-terminate OK
    case systemServiceCritical   // launchd, WindowServer - never touch
    case backgroundSync          // iCloud, Dropbox - can pause
    case userApplication         // Music, Photos - ask user
    case developerTool           // Xcode, git - warn about data loss
    case unknown                 // Unknown process - ask user
}

public actor BlockerDetector {

    /// Detect all processes with open files on the given volume
    public func detectBlockers(volumePath: String) async -> [BlockingProcess] {
        // Use proc_listallpids to get all PIDs
        // Use proc_pidinfo to get process info
        // Use proc_pidfdinfo to get open file descriptors
        // Filter to files on volumePath
        // Classify each process
    }

    /// Classify a process based on its name and behavior
    private func classify(_ processName: String) -> ProcessCategory {
        switch processName {
        case "mds", "mds_stores", "mdworker", "mdworker_shared":
            return .systemServiceSafe
        case "photoanalysisd", "photolibraryd":
            return .systemServiceSafe
        case "bird", "cloudd", "nsurlsessiond":
            return .backgroundSync
        case "launchd", "kernel_task", "WindowServer", "loginwindow":
            return .systemServiceCritical
        case "Xcode", "Code", "git", "swift":
            return .developerTool
        case "Music", "Photos", "Preview", "QuickLook":
            return .userApplication
        default:
            return .unknown
        }
    }
}
```

#### 2. TerminationPlanner

```swift
// swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/TerminationPlanner.swift

public enum TerminationStrategy: Sendable {
    case pause              // SIGSTOP - can resume with SIGCONT
    case gracefulQuit       // SIGTERM - app can save and exit
    case forceQuit          // SIGKILL - immediate termination
    case skip               // Don't touch this process
}

public struct TerminationPlan: Sendable {
    public let actions: [TerminationAction]
    public let requiresUserConfirmation: Bool
    public let estimatedTime: TimeInterval
}

public struct TerminationAction: Sendable {
    public let process: BlockingProcess
    public let strategy: TerminationStrategy
    public let recoveryStrategy: RecoveryStrategy
}

public enum RecoveryStrategy: Sendable {
    case resume             // Send SIGCONT
    case relaunch           // Launch app again
    case none               // No recovery needed
}

public actor TerminationPlanner {

    public func buildPlan(
        blockers: [BlockingProcess],
        policy: BlockerPolicy
    ) -> TerminationPlan {
        var actions: [TerminationAction] = []
        var needsConfirmation = false

        for blocker in blockers {
            let (strategy, recovery) = determineStrategy(blocker, policy: policy)

            if strategy != .skip {
                actions.append(TerminationAction(
                    process: blocker,
                    strategy: strategy,
                    recoveryStrategy: recovery
                ))
            }

            if blocker.category == .userApplication || blocker.category == .unknown {
                needsConfirmation = policy.confirmUserApps
            }
        }

        return TerminationPlan(
            actions: actions,
            requiresUserConfirmation: needsConfirmation,
            estimatedTime: estimateTime(actions)
        )
    }

    private func determineStrategy(
        _ blocker: BlockingProcess,
        policy: BlockerPolicy
    ) -> (TerminationStrategy, RecoveryStrategy) {
        switch blocker.category {
        case .systemServiceSafe:
            return (.pause, .resume)
        case .systemServiceCritical:
            return (.skip, .none)
        case .backgroundSync:
            return (.pause, .resume)
        case .userApplication:
            return policy.autoQuitUserApps ? (.gracefulQuit, .relaunch) : (.skip, .none)
        case .developerTool:
            return (.skip, .none)  // Too risky
        case .unknown:
            return (.skip, .none)  // Ask user
        }
    }
}
```

#### 3. ProcessTerminator

```swift
// swift/Packages/SwiftDiskArbitration/Sources/SwiftDiskArbitration/ProcessTerminator.swift

import Darwin

public actor ProcessTerminator {

    public func execute(_ plan: TerminationPlan) async -> [TerminatedProcess] {
        var terminated: [TerminatedProcess] = []

        for action in plan.actions {
            let success = await terminate(action.process.pid, strategy: action.strategy)

            if success {
                terminated.append(TerminatedProcess(
                    pid: action.process.pid,
                    name: action.process.name,
                    strategy: action.strategy,
                    recoveryStrategy: action.recoveryStrategy
                ))
            }
        }

        return terminated
    }

    private func terminate(_ pid: pid_t, strategy: TerminationStrategy) async -> Bool {
        switch strategy {
        case .pause:
            return kill(pid, SIGSTOP) == 0

        case .gracefulQuit:
            kill(pid, SIGTERM)
            // Wait up to 5 seconds for process to exit
            return await waitForExit(pid, timeout: 5.0)

        case .forceQuit:
            return kill(pid, SIGKILL) == 0

        case .skip:
            return true
        }
    }

    public func recover(_ processes: [TerminatedProcess]) async {
        for process in processes {
            switch process.recoveryStrategy {
            case .resume:
                kill(process.pid, SIGCONT)
            case .relaunch:
                await relaunchApp(process.name)
            case .none:
                break
            }
        }
    }

    private func relaunchApp(_ name: String) async {
        // Use NSWorkspace to relaunch the app
        // This requires AppKit, so may need to be in the plugin layer
    }
}
```

### Settings Integration

Add to `EjectActionSettings`:

```swift
// swift-plugin/Sources/EjectAllDisksPlugin/Actions/EjectAction.swift

struct EjectActionSettings: Codable, Hashable, Sendable {
    var showTitle: Bool = true

    // NEW: Blocker handling settings
    var handleBlockers: Bool = true
    var blockerMode: BlockerMode = .automatic
    var autoPauseSpotlight: Bool = true
    var autoPausePhotos: Bool = true
    var autoQuitMusic: Bool = false
    var showBlockerNotification: Bool = true
    var recoverAfterEject: Bool = true
}

enum BlockerMode: String, Codable, Sendable {
    case automatic      // Auto-handle safe processes, ask for others
    case aggressive     // Auto-handle most processes
    case conservative   // Ask before any termination
    case disabled       // Never terminate (current behavior)
}
```

### Property Inspector UI

Update `ui/eject-all-disks.html`:

```html
<div class="sdpi-item">
    <div class="sdpi-item-label">Blocker Handling</div>
    <select class="sdpi-item-value" id="blockerMode">
        <option value="automatic">Automatic (Recommended)</option>
        <option value="aggressive">Aggressive</option>
        <option value="conservative">Ask Always</option>
        <option value="disabled">Disabled</option>
    </select>
</div>

<div class="sdpi-item" type="checkbox">
    <div class="sdpi-item-label">Auto-pause Spotlight</div>
    <input class="sdpi-item-value" id="autoPauseSpotlight" type="checkbox" checked>
</div>

<div class="sdpi-item" type="checkbox">
    <div class="sdpi-item-label">Auto-pause Photos analysis</div>
    <input class="sdpi-item-value" id="autoPausePhotos" type="checkbox" checked>
</div>

<div class="sdpi-item" type="checkbox">
    <div class="sdpi-item-label">Recover processes after eject</div>
    <input class="sdpi-item-value" id="recoverAfterEject" type="checkbox" checked>
</div>
```

---

## Implementation Phases

### Phase 1: Blocker Detection (1-2 days)

- [ ] Implement `BlockerDetector` using `libproc` APIs
- [ ] Create process classification database
- [ ] Add file handle analysis
- [ ] Unit tests for detection

**Deliverable:** Can detect and classify blocking processes in <50ms

### Phase 2: Termination Engine (2-3 days)

- [ ] Implement `TerminationPlanner`
- [ ] Implement `ProcessTerminator`
- [ ] Add pause/resume logic
- [ ] Add graceful quit with timeout
- [ ] Unit tests for termination

**Deliverable:** Can safely terminate blocking processes

### Phase 3: Integration (1-2 days)

- [ ] Integrate into `DiskSession.ejectAll()`
- [ ] Add settings to `EjectAction`
- [ ] Update Property Inspector UI
- [ ] Add recovery logic

**Deliverable:** Feature works end-to-end

### Phase 4: Polish (1 day)

- [ ] Performance optimization
- [ ] Error handling edge cases
- [ ] Logging and diagnostics
- [ ] Documentation

**Deliverable:** Production-ready feature

---

## Safety Guarantees

### Never Touch List

These processes will NEVER be terminated:

```swift
private let neverTerminate: Set<String> = [
    "launchd",
    "kernel_task",
    "WindowServer",
    "loginwindow",
    "systemstats",
    "configd",
    "diskarbitrationd",
    "coreaudiod"
]
```

### Data Loss Prevention

1. **Check for unsaved work** before quitting user apps (if possible via accessibility APIs)
2. **Prefer pause over kill** - paused processes keep their state
3. **Wait for graceful quit** - give apps time to save
4. **User confirmation** for unknown processes

---

## Performance Targets

| Scenario | Target | Notes |
|----------|--------|-------|
| No blockers | <100ms overhead | Fast path unchanged |
| Safe blockers only | <300ms additional | Pause is instant |
| User app blockers | <2s additional | Graceful quit timeout |
| With recovery | +100ms after eject | Resume is instant |

---

## Open Questions

1. **Should we show a confirmation dialog in Stream Deck?**
   - Stream Deck SDK has limited UI capabilities
   - Could show on button itself (tap to confirm)
   - Or use system notification with actions

2. **How to handle apps that won't quit gracefully?**
   - Force quit after timeout?
   - Ask user?
   - Skip and report failure?

3. **Should we integrate with macOS's built-in "close all apps" for volume?**
   - Finder sends this notification before ejecting
   - Could replicate this behavior

---

## References

- [libproc APIs](https://opensource.apple.com/source/xnu/xnu-4570.71.2/libsyscall/wrappers/libproc/)
- [Signal Handling](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html)
- [DiskArbitration Framework](https://developer.apple.com/documentation/diskarbitration)
- [StreamDeckPlugin Library](https://github.com/emorydunn/StreamDeckPlugin)

---

*This PRD is for future implementation. The current plugin handles blocker failures with error messages only.*
