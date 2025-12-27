# Claude Development Guidelines

This document contains important guidelines for Claude (AI assistant) when working on this codebase.

## Swift Development Requirements

### CRITICAL: Always Validate Swift Code Before Committing

**MANDATORY:** Before committing any changes to Swift files, you MUST verify the code compiles successfully.

#### Required Process:

1. **After making Swift changes**, run syntax/compilation check
2. **Only if successful**, commit the changes
3. **Never skip this step** - compilation errors waste the user's time

#### How to Check:

Since the development environment is Linux (no Swift compiler available), you must:

1. **Static Analysis**: Carefully review Swift 6 strict concurrency requirements:
   - All types passed through `TaskGroup` must conform to `Sendable`
   - `Any`, `AnyObject`, and dictionaries with `Any` values are NOT Sendable
   - Use `@unchecked Sendable` only when truly safe
   - Avoid capturing mutable state across async boundaries

2. **Common Swift 6 Pitfalls**:
   - ❌ `withTaskGroup(of: [String: Any].self)` - Dictionary with Any is not Sendable
   - ✅ `withTaskGroup(of: (String, Bool).self)` - Tuple of Sendable types
   - ❌ Passing closure-captured variables across actor boundaries
   - ✅ Use `nonisolated` functions or pass data explicitly

3. **Review Before Commit**:
   - Check all `withTaskGroup` calls use Sendable types
   - Verify actor isolation boundaries are respected
   - Ensure no implicit captures of non-Sendable data
   - Review any `@unchecked Sendable` usage for actual safety

#### User's Build Process:

The user builds on macOS with:
```bash
cd swift
./build.sh
```

If compilation fails, it creates significant friction as they must:
1. Report the error back to Claude
2. Wait for Claude to fix it
3. Pull changes and rebuild
4. Repeat if there are more errors

**This is unacceptable.** Always validate before committing.

## Why This Matters

- **Swift 6** has strict concurrency checking that catches issues at compile time
- **Sendable violations** are the most common error when using structured concurrency
- **User's time is valuable** - don't make them your compiler error reporter

## Commitment

By following these guidelines, we ensure:
- ✅ Code compiles on first pull
- ✅ No wasted time debugging preventable errors
- ✅ Professional development workflow
- ✅ User confidence in the AI assistant

---

*Last updated: 2025-12-27*
*This document should be consulted before every Swift commit.*
