# Product Requirements Document
## Smart Pre-Ejection Blocker Termination

**Version:** 1.0
**Date:** 2025-12-27
**Status:** Proposal - Awaiting Review
**Author:** Claude
**Stakeholders:** Product Owner, Development Team

---

## Executive Summary

Design and implement an intelligent blocker termination system that **surpasses Jettison** in both speed and effectiveness while maintaining our performance advantage.

### Key Differentiators vs Jettison

| Feature | Jettison | Our Implementation |
|---------|----------|-------------------|
| **Blocker Detection** | `lsof` + `fuser` subprocess (~400ms) | Native `libproc` APIs (~50ms) | **8x faster** |
| **Process Intelligence** | Hardcoded kill list | Dynamic analysis + safe/unsafe classification | **Smarter** |
| **Termination Strategy** | Kill only | Pause → Graceful quit → Force kill cascade | **More reliable** |
| **User Control** | All-or-nothing | Per-process policies, user approval | **More flexible** |
| **Recovery** | Relaunch Music/Photos | Smart recovery for all affected apps | **More comprehensive** |
| **Performance Impact** | +750-2500ms | +50-200ms (when no blockers) | **10x faster** |

### Success Metrics

- **Speed:** <100ms overhead when no blockers present
- **Effectiveness:** >95% first-attempt success rate (vs ~85% for Jettison)
- **User Satisfaction:** <5% of users need manual intervention
- **Safety:** Zero data loss incidents

---

## Problem Statement

### Current State

Users experience ejection failures when processes have files open on the disk:
- **Spotlight indexing** (`mds`, `mds_stores`, `mdworker`)
- **Photos analysis** (`photoanalysisd`)
- **iCloud sync** (`bird`, `cloudd`)
- **Time Machine** (`backupd`)
- **User applications** (Music, Photos, Preview, etc.)

### Current Limitations

1. ❌ User must manually quit blocking processes
2. ❌ No intelligence about which processes are safe to terminate
3. ❌ Error messages don't provide actionable solutions
4. ❌ Lower success rate than Jettison (~60% vs ~85%)
5. ❌ Poor UX when multiple blockers exist

### Why Jettison's Approach Falls Short

1. **Subprocess Overhead:** `lsof` + `fuser` = 200-400ms penalty
2. **Hardcoded Decisions:** Cannot adapt to new processes or user preferences
3. **Coarse-Grained:** Kills processes even when they could be paused
4. **Limited Recovery:** Only relaunches Music/Photos
5. **No User Control:** No way to customize behavior

---

## Goals & Non-Goals

### Goals

1. ✅ Achieve **>95% first-attempt success rate**
2. ✅ Maintain **<100ms overhead** when no blockers present
3. ✅ Be **smarter than Jettison** with dynamic process analysis
4. ✅ Provide **granular user control** over termination policies
5. ✅ Ensure **zero data loss** through safe termination strategies
6. ✅ Support **intelligent recovery** of terminated processes

### Non-Goals

1. ❌ Don't force-kill processes that could cause data loss
2. ❌ Don't require admin privileges for basic functionality
3. ❌ Don't slow down clean ejections (when no blockers exist)
4. ❌ Don't interfere with critical system processes

---

## User Personas

### Persona 1: Professional Creative (Primary)

**Name:** Sarah, Video Editor
**Use Case:** Ejecting external SSDs with large video files
**Pain Points:**
- Premiere Pro, Final Cut Pro often keep file handles open
- Spotlight indexes new footage aggressively
- Time Machine backs up work in progress
- Needs fast ejection between shoots

**Needs:**
- Quick ejection even with active processes
- Won't corrupt project files
- Minimal interruption to workflow
- Smart handling of creative apps

### Persona 2: Developer (Secondary)

**Name:** Alex, Software Engineer
**Use Case:** Ejecting development drives with source code
**Pain Points:**
- IDEs (VS Code, Xcode) keep project files open
- Git operations in background
- Terminal sessions with CWD on external drive
- Docker volumes on external storage

**Needs:**
- Safe handling of version control
- Won't corrupt repositories
- Graceful IDE shutdown
- Fast iteration (frequent eject/mount cycles)

### Persona 3: Casual User (Tertiary)

**Name:** Jordan, Student
**Use Case:** Ejecting USB drives with documents
**Pain Points:**
- Photos app analyzing images
- Spotlight indexing new files
- Preview app with PDFs open
- Dropbox syncing

**Needs:**
- "It just works" experience
- Don't care about technical details
- Want reliable ejection
- Minimal configuration

---

## Detailed Requirements

### 1. Fast Native Process Detection

**Requirement ID:** FR-001
**Priority:** P0 (Critical)

**Description:**
Use native `libproc` APIs to detect blocking processes with minimal overhead.

**Acceptance Criteria:**
- Detection completes in <50ms for typical cases
- Identifies all processes with open file handles on volume
- Provides process details: PID, name, user, file paths
- Works without admin privileges

**Technical Approach:**
```swift
// Already implemented in EjectDisks.swift:132-204
func getBlockingProcesses(path: String) -> [ProcessInfoOutput] {
    // Uses proc_listallpids, proc_pidinfo, proc_pidfdinfo
    // Direct kernel queries, no subprocess
}
```

**Rationale:**
8x faster than Jettison's `lsof` + `fuser` approach. This is our key performance advantage.

---

### 2. Intelligent Process Classification

**Requirement ID:** FR-002
**Priority:** P0 (Critical)

**Description:**
Classify blocking processes into categories with different termination strategies.

**Process Categories:**

| Category | Examples | Strategy | Rationale |
|----------|----------|----------|-----------|
| **System Services (Safe)** | `mds`, `mds_stores`, `mdworker`, `photoanalysisd` | Auto-pause or kill | Automatically restart by macOS |
| **System Services (Critical)** | `launchd`, `WindowServer`, `kernel_task` | Never touch | Would crash system |
| **Background Sync** | `bird`, `cloudd`, `Dropbox` | Graceful pause | Can resume later |
| **User Applications** | Music, Photos, Preview | Ask user or auto-quit | User may have unsaved work |
| **Developer Tools** | `git`, Docker, IDEs | Warn user | May have uncommitted changes |
| **Unknown Processes** | Custom apps | Ask user | Unknown safety profile |

**Acceptance Criteria:**
- Correctly classifies 100% of common macOS processes
- Provides fallback for unknown processes
- Classification completes in <10ms
- Extensible for new processes

**Technical Approach:**
```swift
enum ProcessCategory {
    case systemServiceSafe       // Auto-kill OK
    case systemServiceCritical   // Never touch
    case backgroundSync          // Graceful pause
    case userApplication         // Ask or auto-quit
    case developerTool           // Warn about data loss
    case unknown                 // User decision
}

struct ProcessPolicy {
    let category: ProcessCategory
    let canAutoTerminate: Bool
    let requiresUserConfirmation: Bool
    let recoveryStrategy: RecoveryStrategy
}
```

---

### 3. Graceful Termination Cascade

**Requirement ID:** FR-003
**Priority:** P0 (Critical)

**Description:**
Attempt multiple termination strategies in order of safety.

**Termination Cascade:**

1. **Pause (0-100ms):** Send SIGSTOP to pause process temporarily
   - Best for: Spotlight, Photos analysis
   - Resume with SIGCONT if ejection fails

2. **Graceful Quit (100-500ms):** Send SIGTERM and wait
   - Best for: User applications
   - Allows app to save state

3. **Force Quit (500-1000ms):** Send SIGKILL
   - Last resort only
   - Only for safe system services

4. **Skip:** For critical processes or user-declined terminations
   - Report to user
   - Suggest manual intervention

**Acceptance Criteria:**
- Always tries pause first for pausable processes
- Waits appropriate time for graceful quit
- Never force-quits apps with unsaved data
- Reports cascade progress to user

**Technical Approach:**
```swift
enum TerminationStrategy {
    case pause              // SIGSTOP
    case gracefulQuit       // SIGTERM + wait
    case forceQuit          // SIGKILL
    case skip               // Don't touch
}

func terminateProcess(
    pid: pid_t,
    strategy: TerminationStrategy,
    timeout: TimeInterval
) async -> TerminationResult {
    switch strategy {
    case .pause:
        kill(pid, SIGSTOP)
        return .paused

    case .gracefulQuit:
        kill(pid, SIGTERM)
        // Wait for process to exit
        let exited = await waitForExit(pid, timeout: timeout)
        return exited ? .terminated : .timeout

    case .forceQuit:
        kill(pid, SIGKILL)
        return .killed

    case .skip:
        return .skipped
    }
}
```

---

### 4. User Control & Policies

**Requirement ID:** FR-004
**Priority:** P1 (High)

**Description:**
Allow users to configure termination behavior per process or category.

**Policy Options:**

1. **Automatic Mode** (Default)
   - Auto-pause: Spotlight, Photos analysis
   - Auto-quit: Music, Photos (if no unsaved work)
   - Ask user: Everything else

2. **Aggressive Mode**
   - Auto-terminate all safe processes
   - Only ask for developer tools
   - Maximum success rate

3. **Conservative Mode**
   - Ask before any termination
   - User has full control
   - May fail more often

4. **Custom Mode**
   - Per-process rules
   - User defines policies
   - Advanced users only

**Acceptance Criteria:**
- Settings UI in Property Inspector
- Policies persist across sessions
- Can override per-eject (hold Option key)
- Sensible defaults for 90% of users

**UI Design:**
```
┌─────────────────────────────────────────┐
│ Smart Blocker Termination               │
├─────────────────────────────────────────┤
│                                         │
│ Mode: ● Automatic                       │
│       ○ Aggressive                      │
│       ○ Conservative                    │
│       ○ Custom                          │
│                                         │
│ ☑ Auto-pause Spotlight indexing         │
│ ☑ Auto-pause Photos analysis            │
│ ☑ Auto-quit Music (if safe)             │
│ ☑ Auto-quit Photos (if safe)            │
│ ☐ Auto-pause iCloud sync                │
│ ☐ Auto-pause Time Machine                │
│                                         │
│ ☑ Show notification when processes      │
│   are terminated                        │
│                                         │
│ ☑ Recover terminated processes after    │
│   ejection                              │
└─────────────────────────────────────────┘
```

---

### 5. Intelligent Recovery

**Requirement ID:** FR-005
**Priority:** P1 (High)

**Description:**
Automatically recover processes that were terminated for ejection.

**Recovery Strategies:**

| Process Type | Recovery Action | Timing |
|--------------|----------------|--------|
| **Spotlight** | Auto-resumes | Immediately after eject |
| **Photos Analysis** | Auto-resumes | Immediately after eject |
| **Music/Photos App** | Relaunch if was running | 2 seconds after eject |
| **Background Sync** | Resume (SIGCONT) | Immediately after eject |
| **User Apps** | Ask user to relaunch | Show notification |

**Acceptance Criteria:**
- Tracks which processes were terminated
- Recovers automatically when safe
- Asks user for applications
- Restores previous state when possible

**Technical Approach:**
```swift
struct TerminatedProcess {
    let pid: pid_t
    let name: String
    let bundleID: String?
    let wasRunning: Bool
    let terminationStrategy: TerminationStrategy
    let timestamp: Date
}

func recoverTerminatedProcesses(
    _ processes: [TerminatedProcess]
) async {
    for process in processes {
        switch process.terminationStrategy {
        case .pause:
            // Resume with SIGCONT
            kill(process.pid, SIGCONT)

        case .gracefulQuit:
            // Relaunch if was user app
            if let bundleID = process.bundleID {
                await NSWorkspace.shared.launchApplication(
                    withBundleIdentifier: bundleID
                )
            }

        default:
            break
        }
    }
}
```

---

### 6. File Handle Analysis

**Requirement ID:** FR-006
**Priority:** P2 (Medium)

**Description:**
Analyze what files are open and how (read-only vs read-write).

**Why This Matters:**
- Read-only handles (Spotlight indexing) are safer to interrupt
- Write handles (active editing) risk data loss
- Can make smarter termination decisions

**File Handle Types:**

1. **Read-Only:** Safe to interrupt
   - Spotlight reading for indexing
   - Preview displaying document
   - Media player reading video

2. **Write Active:** Potentially unsafe
   - Photo editor saving changes
   - Database writing
   - Active file sync

3. **Write Buffered:** May be unsafe
   - App with unsaved changes
   - Write cache not flushed

**Acceptance Criteria:**
- Identifies file handle types using `proc_pidfdinfo`
- Considers handle type in termination decision
- Warns user about write handles
- Suggests "Save All" before ejection

**Technical Approach:**
```swift
struct FileHandle {
    let filePath: String
    let mode: FileMode  // read, write, readWrite
    let isBuffered: Bool
    let processName: String
}

enum FileMode {
    case readOnly    // Safe to interrupt
    case writeOnly   // Unsafe
    case readWrite   // Unsafe
}

func analyzeFileHandles(
    pid: pid_t,
    volumePath: String
) -> [FileHandle] {
    // Use proc_pidfdinfo to get file descriptor info
    // Check vnode flags for read/write mode
    // Return detailed handle information
}
```

---

### 7. Smart Notification System

**Requirement ID:** FR-007
**Priority:** P2 (Medium)

**Description:**
Inform users about termination actions without being annoying.

**Notification Types:**

1. **Silent (Default):**
   - No notification for safe auto-terminations
   - Only show if something unusual happens

2. **Summary:**
   - One notification after ejection
   - "Paused Spotlight and Photos to eject MyDisk"
   - Click for details

3. **Detailed:**
   - Show each action as it happens
   - For debugging or paranoid users

**Acceptance Criteria:**
- Notifications are actionable
- Don't interrupt workflow
- Provide undo if possible
- Link to settings

**UI Examples:**

**Silent Mode:**
```
[No notification - just works]
```

**Summary Mode:**
```
┌────────────────────────────────────────┐
│ 🔌 MyUSB Ejected                        │
├────────────────────────────────────────┤
│ Temporarily paused:                    │
│  • Spotlight indexing                  │
│  • Photos analysis                     │
│                                        │
│ [Details]  [Settings]                  │
└────────────────────────────────────────┘
```

**Detailed Mode:**
```
┌────────────────────────────────────────┐
│ 🔌 Ejecting MyUSB...                    │
├────────────────────────────────────────┤
│ ⏸️  Paused: Spotlight (mds_stores)      │
│ ⏸️  Paused: Photos analysis             │
│ ✅ Ejected successfully                 │
│ ▶️  Resumed: All processes              │
│                                        │
│ [Settings]                             │
└────────────────────────────────────────┘
```

---

### 8. Performance Optimization

**Requirement ID:** FR-008
**Priority:** P0 (Critical)

**Description:**
Maintain speed advantage over Jettison while adding intelligence.

**Performance Targets:**

| Scenario | Target Time | Current (No Blocker) | Jettison |
|----------|-------------|---------------------|----------|
| **No blockers** | <100ms | ~600ms | ~3000ms |
| **With safe blockers** | <800ms | N/A | ~3500ms |
| **With user apps** | <1500ms | N/A | ~4000ms |

**Optimization Strategies:**

1. **Lazy Evaluation:**
   - Only detect blockers if first eject fails
   - Skip analysis for clean ejections

2. **Parallel Analysis:**
   - Check all processes simultaneously
   - Use TaskGroup for concurrency

3. **Caching:**
   - Remember process classifications
   - Cache file handle analysis

4. **Early Exit:**
   - Stop analysis if critical blocker found
   - Don't waste time analyzing all processes

**Acceptance Criteria:**
- Clean ejections remain <100ms (no regression)
- Blocker detection adds <50ms
- Termination adds <200ms per process
- Still 2-3x faster than Jettison overall

---

### 9. Safety Guarantees

**Requirement ID:** FR-009
**Priority:** P0 (Critical)

**Description:**
Ensure zero data loss from blocker termination.

**Safety Rules:**

1. ✅ **Never touch critical system processes**
   - `launchd`, `WindowServer`, `kernel_task`
   - Would crash the system

2. ✅ **Never force-quit apps with unsaved work**
   - Check NSDocument dirty state if possible
   - Ask user before terminating

3. ✅ **Never interrupt active writes**
   - Check file handle modes
   - Wait for write buffers to flush

4. ✅ **Always allow user override**
   - User can decline any termination
   - User can skip blocker termination entirely

5. ✅ **Graceful degradation**
   - If unsure, ask user
   - Err on side of caution

**Acceptance Criteria:**
- Zero reported data loss incidents
- All potentially unsafe actions require user confirmation
- Comprehensive logging for debugging
- Can simulate without executing (dry-run mode)

---

## Technical Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Stream Deck Button                       │
│                    (User presses eject)                      │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  TypeScript Plugin Layer                     │
│  - Receives button press                                     │
│  - Calls Swift binary with options                           │
│  - Displays progress/results                                 │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Swift CLI Binary (eject-disks)              │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 1. Enumerate Volumes                                  │  │
│  │    - Get all ejectable volumes                        │  │
│  │    - Group by physical device                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 2. Attempt Fast Ejection                             │  │
│  │    - Try DADiskUnmount directly                       │  │
│  │    - If success: Done! (600ms)                        │  │
│  │    - If fails: Continue to blocker detection          │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 3. Smart Blocker Detection (NEW)                      │  │
│  │    - Use libproc APIs (50ms)                          │  │
│  │    - Identify all processes with open files           │  │
│  │    - Classify each process (category + policy)        │  │
│  │    - Analyze file handle types (read vs write)        │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 4. Build Termination Plan (NEW)                       │  │
│  │    - For each blocker, determine:                     │  │
│  │      • Strategy (pause/quit/kill/skip)                │  │
│  │      • User confirmation needed?                      │  │
│  │      • Recovery action                                │  │
│  │    - Optimize for minimal interruption                │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 5. Request User Approval (if needed)                  │  │
│  │    - Send plan to TypeScript layer                    │  │
│  │    - Show confirmation dialog                         │  │
│  │    - User can approve/decline/modify                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 6. Execute Termination Plan (NEW)                     │  │
│  │    - Execute in parallel where safe                   │  │
│  │    - Pause → Graceful quit → Force quit cascade       │  │
│  │    - Track all terminated processes                   │  │
│  │    - Report progress                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 7. Retry Ejection                                     │  │
│  │    - Attempt DADiskUnmount again                      │  │
│  │    - Should succeed now (95%+ success rate)           │  │
│  └──────────────────────────────────────────────────────┘  │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 8. Recover Processes (NEW)                            │  │
│  │    - Resume paused processes (SIGCONT)                │  │
│  │    - Relaunch quit applications                       │  │
│  │    - Send recovery notifications                      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                    Return Success/Failure                    │
│  - Update Stream Deck button icon                            │
│  - Show success/error state                                  │
│  - Display notification if configured                        │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. BlockerDetector (Swift)
```swift
actor BlockerDetector {
    func detectBlockers(
        volumePath: String
    ) async -> [BlockingProcess]

    func classifyProcess(
        _ process: ProcessInfo
    ) -> ProcessCategory

    func analyzeFileHandles(
        pid: pid_t,
        volumePath: String
    ) -> [FileHandle]
}
```

#### 2. TerminationPlanner (Swift)
```swift
actor TerminationPlanner {
    func buildPlan(
        blockers: [BlockingProcess],
        policy: TerminationPolicy
    ) -> TerminationPlan

    func optimizePlan(
        _ plan: TerminationPlan
    ) -> TerminationPlan
}
```

#### 3. ProcessTerminator (Swift)
```swift
actor ProcessTerminator {
    func execute(
        plan: TerminationPlan
    ) async -> TerminationResult

    func terminateProcess(
        pid: pid_t,
        strategy: TerminationStrategy
    ) async -> Bool

    func recoverProcesses(
        _ terminated: [TerminatedProcess]
    ) async
}
```

#### 4. UserConfirmationBridge (TypeScript ↔ Swift)
```typescript
interface ConfirmationRequest {
    blockers: BlockingProcess[]
    plan: TerminationPlan
    estimatedTime: number
}

interface ConfirmationResponse {
    approved: boolean
    modifiedPlan?: TerminationPlan
}
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
**Goal:** Core blocker detection and classification

- [ ] Enhance existing `getBlockingProcesses()` with file handle analysis
- [ ] Implement process classification engine
- [ ] Create termination policy system
- [ ] Add comprehensive unit tests
- [ ] Benchmark detection performance

**Deliverables:**
- `BlockerDetector.swift` - Detection and classification
- `ProcessPolicy.swift` - Policy definitions
- Unit tests with 90%+ coverage

**Success Criteria:**
- Detection completes in <50ms
- Correctly classifies 100% of test cases
- Zero false positives/negatives

### Phase 2: Termination Engine (Week 2)
**Goal:** Safe and effective process termination

- [ ] Implement graceful termination cascade
- [ ] Add safety checks and validation
- [ ] Create recovery system
- [ ] Add termination planner
- [ ] Performance optimization

**Deliverables:**
- `ProcessTerminator.swift` - Termination execution
- `TerminationPlanner.swift` - Plan generation
- `RecoveryManager.swift` - Process recovery

**Success Criteria:**
- Zero data loss in testing
- Termination completes in <200ms per process
- 100% recovery success rate for safe processes

### Phase 3: Integration (Week 3)
**Goal:** Wire into existing eject flow

- [ ] Integrate with `DiskSession.ejectAll()`
- [ ] Add command-line flags for testing
- [ ] Create TypeScript bridge for confirmation
- [ ] Update Property Inspector UI
- [ ] Add logging and diagnostics

**Deliverables:**
- Updated `DiskSession.swift` with blocker termination
- Updated `eject-all-disks.ts` with UI hooks
- Property Inspector settings panel

**Success Criteria:**
- No regression in clean eject performance
- Settings persist correctly
- UI responds within 100ms

### Phase 4: Polish & Testing (Week 4)
**Goal:** Production-ready quality

- [ ] Comprehensive integration testing
- [ ] User acceptance testing
- [ ] Performance profiling and optimization
- [ ] Documentation and examples
- [ ] Release preparation

**Deliverables:**
- Test suite with real-world scenarios
- Performance benchmark report
- User documentation
- Marketing materials

**Success Criteria:**
- >95% success rate in real-world testing
- All performance targets met
- Zero critical bugs

---

## Success Metrics

### Performance KPIs

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Clean eject time** | <100ms | Benchmark with no blockers |
| **Blocker detection time** | <50ms | Benchmark with 10 processes |
| **Termination time** | <200ms/process | Average across process types |
| **Overall success rate** | >95% | Real-world testing, 1000 ejects |
| **User satisfaction** | >90% positive | User surveys |

### Quality KPIs

| Metric | Target | How to Measure |
|--------|--------|----------------|
| **Data loss incidents** | 0 | User reports + testing |
| **Crashes from termination** | 0 | Crash reports |
| **False blocker detections** | <1% | Manual verification |
| **Recovery success rate** | >99% | Automated testing |

### Competitive KPIs

| Metric | vs Jettison | How to Measure |
|--------|-------------|----------------|
| **Speed advantage** | 3-5x faster | Side-by-side benchmark |
| **Success rate advantage** | +10% higher | Controlled testing |
| **User preference** | >70% prefer ours | A/B testing |

---

## Risks & Mitigations

### High Risk

**Risk:** Process termination causes data loss
**Probability:** Medium
**Impact:** Critical
**Mitigation:**
- Comprehensive safety checks
- User confirmation for unsafe operations
- Extensive testing with real apps
- Graceful termination with timeouts
- Disable by default, opt-in for aggressive mode

**Risk:** System instability from killing wrong process
**Probability:** Low
**Impact:** Critical
**Mitigation:**
- Hardcoded never-kill list (launchd, etc.)
- Process classification validation
- Dry-run mode for testing
- Ability to disable feature entirely

### Medium Risk

**Risk:** Performance regression on clean ejects
**Probability:** Medium
**Impact:** High
**Mitigation:**
- Lazy evaluation (only check on failure)
- Performance benchmarks in CI
- Profile-guided optimization

**Risk:** User annoyance from confirmations
**Probability:** Medium
**Impact:** Medium
**Mitigation:**
- Smart defaults (auto-approve safe operations)
- Remember user preferences
- Silent mode available

### Low Risk

**Risk:** Recovery fails to relaunch apps
**Probability:** Low
**Impact:** Low
**Mitigation:**
- Graceful failure handling
- User notification with manual relaunch option
- Log recovery failures for debugging

---

## Open Questions

1. **Should we support custom process rules?**
   - Pro: Power users can optimize for their workflow
   - Con: Complexity, maintenance burden
   - **Proposal:** Phase 2 feature if users request it

2. **How aggressive should default mode be?**
   - Option A: Very conservative (ask for everything)
   - Option B: Moderate (auto-kill safe system services only)
   - Option C: Aggressive (auto-kill most things)
   - **Proposal:** Option B with easy toggle to A or C

3. **Should we integrate with macOS Activity Monitor?**
   - Pro: Could show "Energy Impact" to user
   - Con: Additional complexity
   - **Proposal:** No, keep it simple

4. **Should we support scheduled termination?**
   - Example: "Pause Spotlight every evening at 5pm"
   - **Proposal:** Out of scope, focus on eject-time termination

5. **Should we provide an API for other apps?**
   - Allow other apps to use our blocker detection
   - **Proposal:** Phase 2 if there's demand

---

## Appendix

### A. Process Classification Database

**Safe System Services:**
```
mds, mds_stores, mdworker       # Spotlight - auto-restarts
photoanalysisd                  # Photos - can pause
bird, cloudd                    # iCloud - can pause
```

**Critical System Processes (Never Touch):**
```
launchd, kernel_task           # System core
WindowServer                   # GUI
loginwindow                    # Login
systemstats, configd          # System daemons
```

**User Applications:**
```
Music, Photos, Preview         # Apple apps - ask or auto-quit
Safari, Chrome, Firefox        # Browsers - ask
Code, Xcode                    # IDEs - warn about unsaved
```

**Background Sync:**
```
Dropbox, Google Drive          # File sync - can pause
backupd                        # Time Machine - can pause
```

### B. Termination Timeouts

| Strategy | Timeout | Fallback |
|----------|---------|----------|
| Pause | Immediate | N/A |
| Graceful Quit | 5 seconds | Force quit |
| Force Quit | 2 seconds | Report failure |

### C. Recovery Delays

| Process Type | Delay | Reason |
|--------------|-------|--------|
| System Services | Immediate | Will auto-restart |
| Background Sync | Immediate | Resume ASAP |
| User Apps | 2 seconds | Give eject time to complete |

### D. References

- [macOS Process Management](https://developer.apple.com/library/archive/technotes/tn2050/_index.html)
- [Signal Handling in macOS](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/signal.3.html)
- [Jettison Technical Analysis](../PERFORMANCE_ANALYSIS.md)
- [DiskArbitration Framework](https://developer.apple.com/documentation/diskarbitration)

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-27 | Initial PRD draft |

---

## Approval

**Awaiting Review From:**
- [ ] Product Owner
- [ ] Lead Developer
- [ ] UX Designer
- [ ] QA Lead

**Sign-off:**
- Product Owner: _________________ Date: _______
- Lead Developer: ________________ Date: _______
