# CLAUDE.md - AI Assistant Development Guidelines

**Last Updated:** 2025-12-27

This document captures critical guidelines and lessons learned to prevent inefficiencies, reduce back-and-forth, and ensure high-quality contributions to this codebase.

---

## CRITICAL REQUIREMENTS

### 1. Swift Code Validation (MANDATORY)

**NEVER commit Swift code without validating it first.**

#### The Problem:
In this session, I committed Swift code with Sendable conformance errors, forcing the user to:
1. Pull the code
2. Attempt to build
3. Report compilation errors back to me
4. Wait for a fix
5. Rebuild

**This wasted significant time and broke trust.**

#### The Solution:
Before committing ANY Swift code changes:

1. **Review Swift 6 Strict Concurrency Requirements:**
   - All types passed through `withTaskGroup` MUST be `Sendable`
   - Common non-Sendable types:
     - `Any`, `AnyObject`
     - `[String: Any]` (dictionaries with Any values)
     - Closures capturing mutable state
     - Classes without `@unchecked Sendable` (use sparingly)

2. **Mental Compilation Checklist:**
   ```
   ☐ All TaskGroup types are Sendable (String, Int, Bool, custom Sendable structs)
   ☐ No implicit captures of non-Sendable data across async boundaries
   ☐ Actor isolation boundaries are respected
   ☐ No use of @unchecked Sendable without clear safety justification
   ☐ All async functions properly marked and await calls are correct
   ```

3. **Common Patterns:**
   - ❌ BAD: `withTaskGroup(of: [String: Any].self)`
   - ✅ GOOD: `withTaskGroup(of: (String, Bool).self)`
   - ❌ BAD: Capturing `var` from outside closure in TaskGroup
   - ✅ GOOD: Pass all data as parameters or use `let` constants

#### Why I Failed:
- I was in a Linux environment without Swift compiler
- I rushed to implement the mount command
- I didn't mentally validate the Sendable conformance

#### How to Prevent:
- **ALWAYS** mentally compile before committing
- **NEVER** assume "it should work"
- **THINK** about what types cross async boundaries

---

## Lessons Learned from This Session

### Mistake #1: Swift Sendable Conformance Errors

**What Happened:**
Committed mount command implementation with `withTaskGroup(of: (String, [String: Any]?, [[String: Any]]?).self)` - dictionaries with `Any` are not Sendable.

**Impact:**
- User had to report compilation errors
- Required immediate fix and rebuild
- Wasted 10+ minutes of user time

**How to Prevent:**
- Review EVERY `withTaskGroup` call for Sendable conformance
- Ask: "Can this type be safely sent across async boundaries?"
- When in doubt, use simpler Sendable types (String, Int, Bool, custom structs)

**Correct Approach:**
```swift
// Only pass Sendable data through TaskGroup
let externalDiskIds = await withTaskGroup(of: (String, Bool).self) { group in
    // String and Bool are both Sendable
}

// Process non-Sendable dictionaries outside the TaskGroup
for diskInfo in allDisks {
    // Work with [String: Any] serially
}
```

---

### Mistake #2: Wrong AppleScript Syntax for Jettison

**What Happened:**
Used `tell application "Jettison" to eject all disks` instead of `tell application "Jettison" to eject`

**Error:**
```
37:46: syntax error: A identifier can't go after this identifier. (-2740)
```

**Impact:**
- Multiple test script failures
- User had to report AppleScript errors
- Created test-jettison-mount.sh unnecessarily
- Required fixing 3 files: benchmark-suite.sh, debug-jettison.sh, test-jettison-timing.sh

**How to Prevent:**
- **Research before implementing** - Look up AppleScript API documentation
- **Test incrementally** - Don't commit untested AppleScript commands
- **Follow established patterns** - Check if similar code exists in the repo

**Correct Approach:**
1. Search for "Jettison AppleScript API" documentation first
2. Test the command in a small script before integrating
3. Only commit once verified working

---

### Mistake #3: Inefficient Jettison Detection Evolution

**What Happened:**
1. First used `diskutil list | grep -q 'external, physical'`
2. User reported it might not work
3. I created debug scripts to test detection
4. Turned out the grep pattern DID work
5. Changed to `$BINARY_PATH count` anyway (which was better, but unnecessary pivot)

**Impact:**
- Created extra debug scripts that weren't needed
- Multiple iterations of detection methods
- User confusion about which approach to use

**How to Prevent:**
- **Test assumptions before pivoting** - The original grep DID work
- **Stick with working solutions** - Don't fix what isn't broken
- **When improving, explain why** - Make it clear when optimization is the goal

**Better Approach:**
1. Test the grep pattern first to see if it actually fails
2. If it works, keep it
3. If optimizing, explain: "The grep works, but using binary count is more reliable"

---

### Mistake #4: Wrong File Naming Convention

**What Happened:**
Created `CLAUDE_GUIDELINES.md` instead of `CLAUDE.md`

**Impact:**
- Wrong naming convention
- Had to recreate the file
- Extra commit/push cycle

**How to Prevent:**
- **Ask first** when unsure about conventions
- **Check existing patterns** in the repository
- **CLAUDE.md is the standard** - remember this

---

### Mistake #5: Not Being Proactive About Automation

**What Happened:**
User had to manually remount drives between benchmark runs until they asked: "Can we automate this with Jettison or Swift?"

**Better Approach:**
- Should have suggested the mount command automation IMMEDIATELY
- When I saw "Please remount manually" I should have said:
  - "I can create a mount command in Swift to automate this"
  - "Would you like me to add automatic remounting to the benchmark?"

**Lesson:**
- **Be proactive about automation opportunities**
- **Don't wait for the user to suggest improvements**
- **Think about the full workflow, not just individual commands**

---

## Development Workflow

### Before Starting Any Task

1. **Understand the full context**
   - Read related code
   - Check existing patterns
   - Identify dependencies

2. **Plan the implementation**
   - Think through the approach
   - Identify potential issues
   - Consider Swift 6 concurrency requirements

3. **Validate assumptions**
   - Don't guess API syntax - research it
   - Test patterns before committing
   - Ask the user if uncertain

### During Implementation

1. **Write code incrementally**
   - Small, testable changes
   - Validate as you go
   - Mental compilation checks

2. **For Swift code specifically:**
   ```
   ☐ Are all async boundaries properly handled?
   ☐ Are all TaskGroup types Sendable?
   ☐ Are actor isolation rules followed?
   ☐ Are there any implicit captures?
   ☐ Would this compile with Swift 6 strict concurrency?
   ```

3. **For shell scripts:**
   - Test variable substitution
   - Check quote escaping
   - Verify heredoc syntax
   - Test JSON parsing

### Before Committing

1. **Final validation checklist:**
   ```
   ☐ Swift: Mental compilation check (Sendable, async, actor isolation)
   ☐ Shell: Syntax validation (quotes, pipes, heredocs)
   ☐ AppleScript: Verified syntax against documentation
   ☐ Tests: Would this work in production?
   ☐ Efficiency: Is this the best approach?
   ```

2. **Commit message quality:**
   - Explain WHAT changed
   - Explain WHY it changed
   - Note any breaking changes
   - Reference related issues

3. **Push immediately after commit:**
   - Don't leave unpushed commits
   - User's stop-hook will catch this

---

## Communication Guidelines

### When Uncertain

**DON'T:**
- Guess and commit broken code
- Assume API syntax without checking
- Pivot approaches without testing first

**DO:**
- Ask the user for clarification
- Research documentation first
- Test incrementally before committing

### When Making Mistakes

**DON'T:**
- Make excuses ("I'm in a Linux environment")
- Blame the tools
- Minimize the impact

**DO:**
- Acknowledge the mistake clearly
- Fix it immediately
- Document the lesson learned
- Commit to preventing it

### Being Proactive

**LOOK FOR:**
- Repetitive manual tasks → Automation opportunities
- Hard-coded values → Configuration options
- Multiple similar scripts → Shared functions
- User pain points → Improvement opportunities

**SUGGEST:**
- "I can automate this with..."
- "Would you like me to add..."
- "I notice this could be improved by..."

---

## Swift 6 Strict Concurrency Reference

### Sendable Types (Safe to Pass Through TaskGroup)

✅ **Value Types:**
- `String`, `Int`, `Bool`, `Double`, `Float`
- `Array<T>` where T is Sendable
- `Dictionary<K, V>` where K and V are Sendable
- `Set<T>` where T is Sendable
- Structs marked `Sendable` with only Sendable properties

✅ **Reference Types:**
- Actors (always Sendable)
- Classes marked `@unchecked Sendable` (use with extreme caution)
- Immutable classes with only Sendable properties

❌ **Non-Sendable Types:**
- `Any`, `AnyObject`
- `[String: Any]` (dictionary with Any value)
- Closures capturing mutable state
- Most classes (unless marked `@unchecked Sendable`)
- Structs with non-Sendable properties

### Common Patterns

**Pattern 1: Pass Simple Data, Process Complex Data Outside**
```swift
// ✅ GOOD: Only pass IDs through TaskGroup
let externalIds = await withTaskGroup(of: String.self) { group in
    for item in items {
        group.addTask {
            return getIDIfExternal(item) // Returns String
        }
    }
    // Collect IDs
}

// Process complex data outside TaskGroup
for item in items where externalIds.contains(item.id) {
    // Work with non-Sendable item here
}
```

**Pattern 2: Extract Sendable Data Before TaskGroup**
```swift
// ✅ GOOD: Extract Sendable components
struct DiskInfo: Sendable {
    let identifier: String
    let isExternal: Bool
}

let infos = await withTaskGroup(of: DiskInfo.self) { group in
    // Custom Sendable struct is safe
}
```

**Pattern 3: Avoid Dictionaries with Any**
```swift
// ❌ BAD
withTaskGroup(of: [String: Any].self) // Not Sendable!

// ✅ GOOD
withTaskGroup(of: (String, String, Bool).self) // All Sendable
// Or create custom Sendable struct
```

---

## Repository-Specific Guidelines

### File Naming Conventions

- **This file:** `CLAUDE.md` (all caps)
- **User documentation:** `README.md`, `TESTING.md`, etc.
- **Implementation docs:** `PERFORMANCE_ANALYSIS.md`, `BENCHMARK_FIXES.md`

### Swift Project Structure

- **Main binary:** `swift/Sources/EjectDisks.swift`
- **Library:** `swift/Packages/SwiftDiskArbitration/`
- **Build script:** `swift/build.sh`
- **Binary output:** `org.deverman.ejectalldisks.sdPlugin/bin/eject-disks`

### Benchmark Scripts

- **Main suite:** `benchmark/benchmark-suite.sh`
- **Debug scripts:** `benchmark/debug-*.sh`
- **Test scripts:** `benchmark/test-*.sh`
- **Results:** `benchmark/results/`

### Git Workflow

- **Branch naming:** `claude/analyze-competitor-plugin-Jc7fU` (specific to session)
- **Always push after commit** (stop-hook will catch unpushed commits)
- **Commit early, commit often**
- **Never force push to main/master**

---

## Quality Checklist

Before marking any task complete:

```
☐ Code compiles (mental check for Swift)
☐ Scripts have correct syntax (quotes, pipes, heredocs)
☐ All changes are committed
☐ All commits are pushed
☐ Documentation is updated if needed
☐ User feedback is incorporated
☐ No known bugs or issues
☐ Proactive suggestions offered
```

---

## Reflection: How This Session Could Have Been Better

### What Went Wrong:
1. Swift Sendable errors (wasted 10+ min)
2. AppleScript syntax errors (wasted 15+ min)
3. Unnecessary detection method pivots (wasted 20+ min)
4. Wrong file naming (wasted 5+ min)
5. Not proactively suggesting mount automation (wasted potential)

**Total Waste:** ~50+ minutes of user time

### What Should Have Happened:

**Ideal Flow:**
1. User asks about Jettison automation
2. I research Jettison AppleScript API first
3. I validate Swift mount code for Sendable conformance
4. I commit working, tested code
5. User pulls, builds, runs successfully first time
6. Benchmark runs fully automated with no manual intervention

**Result:** Task complete in 1/3 the time, zero frustration

### Key Takeaway:

**Measure twice, cut once.**
- Research before implementing
- Validate before committing
- Think before coding

The time spent validating upfront is ALWAYS less than the time wasted fixing preventable errors.

---

## Commitment to Excellence

This document exists because I failed to meet the standard expected of a professional AI assistant. These failures:
- Wasted the user's valuable time
- Created frustration and back-and-forth
- Broke trust in my ability to deliver quality code

**Going forward:**
- Every commit will be validated before pushing
- Every API will be researched before using
- Every assumption will be tested before relying on it
- Every opportunity for improvement will be surfaced proactively

**The user deserves code that works the first time, every time.**

This is my commitment.

---

*This document should be consulted before every coding session and updated with new lessons learned.*
