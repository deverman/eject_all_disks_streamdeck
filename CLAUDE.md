# CLAUDE.md - AI Assistant Guide for Stream Deck Plugin Development

This document provides architectural guidance and critical gotchas for AI assistants (or developers) working on this Stream Deck plugin that calls Swift command-line binaries.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Critical Gotchas - Read This First](#critical-gotchas---read-this-first)
3. [Build Pipeline Architecture](#build-pipeline-architecture)
4. [GitHub Actions Release Workflow](#github-actions-release-workflow)
5. [Stream Deck Plugin Structure](#stream-deck-plugin-structure)
6. [Swift Binary Integration](#swift-binary-integration)
7. [Version Management](#version-management)
8. [Common Tasks](#common-tasks)
9. [Troubleshooting Guide](#troubleshooting-guide)

---

## Architecture Overview

This is a **Stream Deck SDK 2.0 (beta)** plugin with these components:

```
┌─────────────────────────────────────────────────┐
│ Stream Deck Application                         │
│  └─> Loads: org.deverman.ejectalldisks.sdPlugin │
│       ├─> Node.js 20 Runtime                    │
│       │    └─> bin/plugin.js (compiled TS)      │
│       └─> Swift Binary                          │
│            └─> bin/eject-disks (native)         │
└─────────────────────────────────────────────────┘
```

**Technology Stack:**
- **Frontend:** TypeScript → JavaScript (via Rollup)
- **Native Binary:** Swift → Compiled executable
- **SDK:** Stream Deck SDK 2.0 (beta) - TypeScript types may be incomplete
- **Platform:** macOS only (uses DiskArbitration framework)
- **Package Format:** `.streamDeckPlugin` (renamed .zip file)

**Build Order (CRITICAL):**
1. Swift binary (`npm run build:swift`) → `bin/eject-disks`
2. TypeScript code (`npm run build`) → `bin/plugin.js`
3. Package plugin (zip) → `dist/org.deverman.ejectalldisks.streamDeckPlugin`

---

## Critical Gotchas - Read This First

### 🚨 Top 10 Issues That WILL Break Your Build

#### 1. **Stream Deck 7.x Package Structure**
```bash
# ❌ WRONG - Files at root
cd org.deverman.ejectalldisks.sdPlugin
zip -r ../plugin.streamDeckPlugin .

# ✅ CORRECT - Include folder name
zip -r plugin.streamDeckPlugin org.deverman.ejectalldisks.sdPlugin
```

**Why:** Stream Deck 7.x expects the .streamDeckPlugin file to contain a folder with the plugin files inside it, not files at the root. Installing a plugin with files at root gives: `"Error: No plugin found in bundle"`

**Location:** `.github/workflows/main.yml` packaging step

---

#### 2. **Swift Binary MUST Be Built BEFORE Node.js Build**
```yaml
# ✅ CORRECT order in GitHub Actions
- name: Build Swift binary
  run: npm run build:swift

- name: Build plugin
  run: npm run build

- name: Verify Swift binary exists
  run: |
    if [ ! -f "org.deverman.ejectalldisks.sdPlugin/bin/eject-disks" ]; then
      echo "Error: Swift binary missing!"
      exit 1
    fi
```

**Why:** The Node.js code expects the Swift binary to exist at `bin/eject-disks`. If you package without the Swift binary, the disk count badge won't work.

**Symptoms:** Plugin installs but no disk count badge appears

---

#### 3. **GitHub Actions Permissions**
```yaml
jobs:
  build-and-package:
    runs-on: macos-latest
    permissions:
      contents: write  # ← REQUIRED for uploading release assets
```

**Why:** Without `contents: write`, uploading to releases fails with `"Resource not accessible by integration"`

**Location:** `.github/workflows/main.yml`

---

#### 4. **Use Modern GitHub Actions**
```yaml
# ❌ DEPRECATED - Will fail
- uses: actions/upload-release-asset@v1

# ✅ CORRECT - Use modern action
- uses: softprops/action-gh-release@v2
  with:
    files: dist/*.streamDeckPlugin
```

**Why:** The old action is deprecated and has authentication issues

---

#### 5. **Don't Commit Build Artifacts**
```bash
# ✅ Must be in .gitignore
dist/
*.streamDeckPlugin
```

**Why:** Committed `dist/` folder from old builds will override your version numbers. Users reported installing "v2.0.0" but seeing "v0.1.0" because an old packaged plugin was committed in May 2025.

**Symptom:** Wrong version showing in Stream Deck after installation

---

#### 6. **manifest.json Version Format**
```json
{
  "Version": "2.0.2.0"  // ← MUST be 4-part format
}
```

**Rules:**
- Git tags: `v2.0.2` (3-part)
- manifest.json: `"2.0.2.0"` (4-part)
- Never modify the `Nodejs.Version` field when bumping plugin version

**Location:** `org.deverman.ejectalldisks.sdPlugin/manifest.json`

---

#### 7. **manifest.json - Invalid Fields Will Break Installation**
```json
{
  "Nodejs": {
    "Version": "20"
    // ❌ NEVER add "Debug": "enabled" here
    // It's not a valid field and breaks installation
  }
}
```

**Symptom:** Plugin won't install or Stream Deck shows validation errors

---

#### 8. **Swift Type Conversions for Process Paths**
```swift
// ❌ WRONG - Type mismatch error
let execPath = String(decoding: pathBuffer, as: UTF8.self)

// ✅ CORRECT - Convert CChar (Int8) to UInt8
let execPath = String(
    bytes: pathBuffer.prefix(Int(pathLen)).map { UInt8(bitPattern: $0) },
    encoding: .utf8
) ?? "unknown"
```

**Why:** `proc_pidpath` returns `CChar` (Int8), but `String(decoding:as:)` expects `UTF8.CodeUnit` (UInt8)

**Symptom:** Swift compilation error in GitHub Actions but not locally (Xcode's Swift version may differ)

**Location:** `swift/Sources/EjectDisks.swift` around line 168

---

#### 9. **Sudoers Path Escaping**
```bash
# ❌ WRONG - Spaces not escaped
/Users/user/Library/Application Support/com.elgato.StreamDeck/...

# ✅ CORRECT - Escape spaces with backslash
/Users/user/Library/Application\ Support/com.elgato.StreamDeck/...
```

**Why:** sudoers file requires escaped spaces. Without this, `sudo -n` will always ask for password.

**Fix in install script:**
```bash
ESCAPED_BINARY=$(echo "$EJECT_BINARY" | sed 's/ /\\ /g')
```

**Location:** `org.deverman.ejectalldisks.sdPlugin/bin/install-eject-privileges.sh`

**Symptom:** Setup script runs successfully but Property Inspector shows "✗ Not configured"

---

#### 10. **SDK 2.0 Beta - Incomplete TypeScript Types**
```typescript
// Stream Deck SDK 2.0 beta has incomplete types
// @ts-ignore - sendToPropertyInspector exists but not in types
await streamDeck.ui.sendToPropertyInspector(response);
```

**Why:** SDK 2.0 is in beta. Some APIs exist at runtime but not in TypeScript definitions.

**Solution:** Use `@ts-ignore` comments for known working APIs

**DO NOT:** Try to fix by using non-existent APIs like `ev.action.sendToPropertyInspector()` or `streamDeck.ui.current?.sendToPropertyInspector()`

---

## Build Pipeline Architecture

### Local Development Build
```bash
npm run build:swift  # Compiles Swift → bin/eject-disks
npm run build        # Compiles TypeScript → bin/plugin.js
```

**Output:**
```
org.deverman.ejectalldisks.sdPlugin/
└── bin/
    ├── plugin.js       # From TypeScript
    └── eject-disks     # From Swift
```

### Watch Mode (Development)
```bash
npm run watch
```

**What it does:**
1. Watches `src/` for TypeScript changes
2. Auto-rebuilds on save
3. Restarts plugin in Stream Deck
4. Does NOT rebuild Swift binary (rebuild manually if Swift changes)

### Production Packaging
```bash
mkdir -p dist
zip -r dist/org.deverman.ejectalldisks.streamDeckPlugin \
  org.deverman.ejectalldisks.sdPlugin \
  -x "*.DS_Store" \
  -x "*/logs/*" \
  -x "*.log" \
  -x "*/.git/*" \
  -x "*/.gitignore" \
  -x "*/pi/*"
```

**Critical:** Include the folder name in the zip, not just its contents

---

## GitHub Actions Release Workflow

**File:** `.github/workflows/main.yml`

### Workflow Trigger
```yaml
on:
  release:
    types: [created]
  push:
    branches: [main]
```

**Runs on:** `macos-latest` (required for Swift compilation)

### Critical Steps

#### 1. Setup
```yaml
- name: Checkout code
  uses: actions/checkout@v4

- name: Setup Node.js
  uses: actions/setup-node@v4
  with:
    node-version: '20'
```

#### 2. Install and Lint
```yaml
- name: Install dependencies
  run: npm ci

- name: Lint code
  run: npm run lint:check  # Fails if Prettier finds issues
```

**Important:** Run `npm run lint:fix` locally before pushing

#### 3. Build (CORRECT ORDER)
```yaml
# ✅ Swift FIRST
- name: Build Swift binary
  run: npm run build:swift

# ✅ Then TypeScript
- name: Build plugin
  run: npm run build

# ✅ Verify binary exists
- name: Verify build output
  run: |
    if [ ! -f "org.deverman.ejectalldisks.sdPlugin/bin/eject-disks" ]; then
      echo "Error: Swift binary eject-disks not found"
      exit 1
    fi
    if [ ! -f "org.deverman.ejectalldisks.sdPlugin/bin/plugin.js" ]; then
      echo "Error: plugin.js not found"
      exit 1
    fi
```

#### 4. Package
```yaml
- name: Package plugin
  run: |
    mkdir -p dist
    zip -r dist/org.deverman.ejectalldisks.streamDeckPlugin \
      org.deverman.ejectalldisks.sdPlugin \
      -x "*.DS_Store" \
      -x "*/logs/*" \
      -x "*.log" \
      -x "*/.git/*" \
      -x "*/.gitignore" \
      -x "*/pi/*"
```

**Key exclusions:**
- `.DS_Store` - macOS metadata
- `logs/*` - Runtime log files
- `*.log` - Any log files
- `.git/*` - Git metadata
- `.gitignore` - Not needed in package
- `pi/*` - Property Inspector development files (if any)

#### 5. Upload to Release
```yaml
- name: Upload to release
  if: github.event_name == 'release'
  uses: softprops/action-gh-release@v2
  with:
    files: dist/*.streamDeckPlugin
```

**Important:** This only runs when a release is created, not on every push

---

## Stream Deck Plugin Structure

### Directory Layout
```
org.deverman.ejectalldisks.sdPlugin/
├── manifest.json          # Plugin metadata - CRITICAL
├── bin/                   # Compiled output
│   ├── plugin.js          # From TypeScript build
│   ├── eject-disks        # From Swift build
│   └── install-eject-privileges.sh  # Privilege setup script
├── ui/                    # Property Inspector
│   └── property-inspector.html
├── imgs/                  # Icons
│   ├── actions/
│   │   ├── eject/        # SVG icons for states
│   └── plugin/           # Plugin icon
└── logs/                  # Runtime logs (auto-created, excluded from package)
```

### manifest.json - Critical Fields

```json
{
  "Name": "Eject All Disks",
  "Version": "2.0.2.0",  // 4-part format
  "Author": "Brent Deverman",
  "UUID": "org.deverman.ejectalldisks",  // Must match folder name

  "Nodejs": {
    "Version": "20"
    // DON'T add Debug field here
  },

  "Actions": [
    {
      "UUID": "org.deverman.ejectalldisks.eject",
      "Name": "Eject All Disks",
      "Icon": "imgs/actions/eject/eject",  // Without extension
      "States": [
        {
          "Image": "imgs/actions/eject/eject"
        }
      ],
      "PropertyInspectorPath": "ui/property-inspector.html"
    }
  ],

  "OS": [
    {
      "Platform": "mac",
      "MinimumVersion": "12.0"
    }
  ],

  "SDKVersion": 2,
  "Software": {
    "MinimumVersion": "6.4"
  }
}
```

**Validation:**
- `UUID` must match plugin folder name pattern
- `Version` must be 4-part (x.y.z.w)
- Icon paths are without extension (.png/.svg auto-detected)
- `SDKVersion: 2` for SDK 2.0 beta

---

## Swift Binary Integration

### Purpose
The Swift binary (`eject-disks`) uses macOS DiskArbitration framework for fast, parallel disk ejection (~6x faster than `diskutil`).

### Build Configuration

**File:** `swift/Package.swift`
```swift
let package = Package(
    name: "EjectDisks",
    platforms: [
        .macOS(.v12)  // Minimum macOS 12
    ],
    products: [
        .executable(
            name: "eject-disks",
            targets: ["EjectDisks"]
        )
    ]
)
```

**Build script in package.json:**
```json
{
  "scripts": {
    "build:swift": "swift build -c release --package-path swift && cp swift/.build/release/eject-disks org.deverman.ejectalldisks.sdPlugin/bin/"
  }
}
```

### Swift → TypeScript Integration

**TypeScript calls Swift binary:**
```typescript
import { spawn } from 'child_process';

const swiftBinary = path.join(__dirname, 'eject-disks');

// Count disks
const countProcess = spawn(swiftBinary, ['list']);

// Eject all
const ejectProcess = spawn('sudo', ['-n', swiftBinary, 'eject', '--verbose']);
```

**Important:**
- Use `sudo -n` for passwordless execution (requires sudoers setup)
- Always provide absolute path to binary
- Handle both stdout and stderr

### Common Swift Issues

**Issue:** Swift compiles locally but fails in GitHub Actions
```
Error: Property 'init(decoding:as:)' requires CChar and UTF8.CodeUnit be equivalent
```

**Cause:** Different Swift versions or stricter type checking

**Fix:** Explicit type conversion
```swift
// Convert CChar (Int8) to UInt8
let bytes = buffer.map { UInt8(bitPattern: $0) }
let str = String(bytes: bytes, encoding: .utf8) ?? "unknown"
```

---

## Version Management

### Version Numbering

**Semantic Versioning (3-part):**
- `MAJOR.MINOR.PATCH` (e.g., `2.0.2`)
- Git tags: `v2.0.2`
- Release titles: `v2.0.2`

**Stream Deck Format (4-part):**
- `MAJOR.MINOR.PATCH.BUILD` (e.g., `2.0.2.0`)
- Used in `manifest.json`
- BUILD is typically `0`

### Version Bump Script

**Command:** `npm run version:bump 2.0.2`

**Script:** `scripts/bump-version.sh`
```bash
#!/bin/bash
VERSION=$1
MANIFEST_VERSION="${VERSION}.0"  # Add .0 for Stream Deck

# ✅ CRITICAL: Only update plugin Version, NOT Nodejs.Version
# Use line range 2,5 to target only the top-level Version field
sed -i '' "2,5s/\"Version\": \"[^\"]*\"/\"Version\": \"$MANIFEST_VERSION\"/" \
  org.deverman.ejectalldisks.sdPlugin/manifest.json
```

**Why the line range:** Without it, sed would also modify `"Nodejs": {"Version": "20"}` to `"Nodejs": {"Version": "2.0.2.0"}`, breaking the plugin.

### Release Process

**Step 1: Bump version**
```bash
npm run version:bump 2.0.2
```

**Step 2: Commit**
```bash
git add org.deverman.ejectalldisks.sdPlugin/manifest.json
git commit -m "Bump version to 2.0.2"
```

**Step 3: Tag and push**
```bash
git tag -a v2.0.2 -m "Release v2.0.2"
git push && git push origin v2.0.2
```

**Step 4: Create GitHub Release**
```bash
gh release create v2.0.2 \
  --title "v2.0.2" \
  --notes "Release notes here"
```

**Step 5: Wait for automation**
- GitHub Actions builds and packages
- `.streamDeckPlugin` file uploaded to release
- Users download from releases page

---

## Common Tasks

### Task 1: Fix TypeScript Code
```bash
# 1. Make changes in src/
vim src/actions/eject-all-disks.ts

# 2. Lint and format
npm run lint:fix

# 3. Build
npm run build

# 4. Test in Stream Deck
npx streamdeck restart org.deverman.ejectalldisks
```

### Task 2: Fix Swift Binary
```bash
# 1. Make changes in swift/
vim swift/Sources/EjectDisks.swift

# 2. Build Swift binary
npm run build:swift

# 3. Verify binary exists
ls -lh org.deverman.ejectalldisks.sdPlugin/bin/eject-disks

# 4. Test in Stream Deck
npx streamdeck restart org.deverman.ejectalldisks
```

### Task 3: Update Dependencies
```bash
# Update npm packages
npm update

# Check for outdated
npm outdated

# Update GitHub Actions
# Edit .github/workflows/main.yml and bump action versions
```

### Task 4: Debug Installation Issues
```bash
# 1. Check Stream Deck logs
tail -f ~/Library/Logs/ElgatoStreamDeck/StreamDeck0.log

# 2. Check plugin logs
tail -f ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin/logs/*.log

# 3. Test package structure
unzip -l dist/org.deverman.ejectalldisks.streamDeckPlugin | head -20
# Should show: org.deverman.ejectalldisks.sdPlugin/manifest.json
# NOT: manifest.json

# 4. Remove quarantine (if needed)
xattr -rc dist/org.deverman.ejectalldisks.streamDeckPlugin
```

### Task 5: Test Sudoers Setup
```bash
# 1. Check if sudoers file exists
ls -l /etc/sudoers.d/eject-disks

# 2. View sudoers rule
sudo cat /etc/sudoers.d/eject-disks

# 3. Test passwordless sudo
sudo -n /path/to/eject-disks --version
# Should NOT ask for password

# 4. If it asks for password, check for spaces in path
# Path should have escaped spaces:
# /Users/user/Library/Application\ Support/com.elgato.StreamDeck/...
```

---

## Troubleshooting Guide

### Issue: Plugin Won't Install

**Symptom:** "Unable to install 'extracted' plugin"

**Check Stream Deck logs:**
```bash
grep -i error ~/Library/Logs/ElgatoStreamDeck/StreamDeck0.log
```

**Common causes:**
1. **Wrong package structure** - Files at root instead of in folder
   ```bash
   # Verify structure
   unzip -l plugin.streamDeckPlugin | head -5
   # Should show: org.deverman.ejectalldisks.sdPlugin/
   ```

2. **Invalid manifest.json** - Syntax error or invalid fields
   ```bash
   # Validate JSON
   cat org.deverman.ejectalldisks.sdPlugin/manifest.json | jq .
   ```

3. **Missing required files**
   ```bash
   # Check plugin.js exists
   ls org.deverman.ejectalldisks.sdPlugin/bin/plugin.js
   ```

---

### Issue: Wrong Version Showing

**Symptom:** Installed v2.0.0 but Stream Deck shows v0.1.0

**Causes:**
1. **Committed dist/ folder** - Old build overriding new one
   ```bash
   git rm -r dist/
   echo "dist/" >> .gitignore
   ```

2. **Didn't rebuild before packaging**
   ```bash
   npm run build:swift
   npm run build
   # Then package
   ```

3. **Version bump didn't work**
   ```bash
   cat org.deverman.ejectalldisks.sdPlugin/manifest.json | grep Version
   # Should show: "Version": "2.0.0.0"
   ```

---

### Issue: Disk Count Badge Not Showing

**Symptom:** Plugin installs but no red badge with disk count

**Causes:**
1. **Swift binary missing from package**
   ```bash
   unzip -l plugin.streamDeckPlugin | grep eject-disks
   # Should show: org.deverman.ejectalldisks.sdPlugin/bin/eject-disks
   ```

2. **Swift binary not built before packaging**
   ```bash
   npm run build:swift
   ls -lh org.deverman.ejectalldisks.sdPlugin/bin/eject-disks
   # Should show ~150KB file
   ```

3. **Permissions issue**
   ```bash
   chmod +x org.deverman.ejectalldisks.sdPlugin/bin/eject-disks
   ```

---

### Issue: GitHub Actions Build Fails

**Swift compilation error:**
```
Error: Property 'init(decoding:as:)' requires CChar and UTF8.CodeUnit be equivalent
```

**Fix:** Use explicit type conversion in Swift code
```swift
let bytes = buffer.map { UInt8(bitPattern: $0) }
```

**Prettier formatting error:**
```
Code style issues found in 12 files
```

**Fix:** Run locally before pushing
```bash
npm run lint:fix
git add .
git commit --amend --no-edit
```

**Release upload fails:**
```
Error: Resource not accessible by integration
```

**Fix:** Add permissions to workflow
```yaml
permissions:
  contents: write
```

---

### Issue: Property Inspector Status Not Updating

**Symptom:** Ran setup script but status still shows "✗ Not configured"

**Causes:**
1. **Sudoers path has unescaped spaces**
   ```bash
   sudo cat /etc/sudoers.d/eject-disks
   # Should show: /path/to/Application\ Support/...
   # NOT: /path/to/Application Support/...
   ```

2. **Setup script outdated** - Need version 2.0.2+
   ```bash
   # Check plugin version
   cat org.deverman.ejectalldisks.sdPlugin/manifest.json | grep Version
   # Should be 2.0.2.0 or higher
   ```

3. **Test manually**
   ```bash
   sudo -n /path/to/eject-disks --version
   # If asks for password, sudoers not configured correctly
   ```

---

## Quick Reference - Pre-Push Checklist

Before pushing code or creating a release:

- [ ] Run `npm run lint:fix` (fixes formatting)
- [ ] Run `npm run build:swift` (builds Swift binary)
- [ ] Run `npm run build` (builds TypeScript)
- [ ] Verify Swift binary exists: `ls -lh */bin/eject-disks`
- [ ] Check manifest.json version is correct
- [ ] Ensure `dist/` is in .gitignore
- [ ] Don't commit any `.streamDeckPlugin` files
- [ ] Test package structure if making packaging changes
- [ ] Update CHANGELOG if releasing

---

## Quick Reference - Release Checklist

When creating a new release:

- [ ] Version bumped: `npm run version:bump X.Y.Z`
- [ ] manifest.json shows correct 4-part version (X.Y.Z.0)
- [ ] Changes committed: `git commit -m "Bump version to X.Y.Z"`
- [ ] Tagged: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Pushed: `git push && git push origin vX.Y.Z`
- [ ] GitHub release created (via web UI or `gh release create`)
- [ ] Wait for GitHub Actions to complete
- [ ] Verify `.streamDeckPlugin` attached to release
- [ ] Download and test installation
- [ ] Check version shows correctly in Stream Deck

---

## Architecture Decision Records

### Why Swift Binary Instead of Pure Node.js?

**Decision:** Use native Swift binary with DiskArbitration framework

**Rationale:**
- ~6x faster than spawning `diskutil` for each disk
- Parallel ejection with Swift concurrency
- Native macOS APIs for reliability
- Can detect blocking processes

**Trade-off:** Requires macOS, adds build complexity

---

### Why SDK 2.0 Beta?

**Decision:** Use Stream Deck SDK 2.0 (beta) instead of stable 1.x

**Rationale:**
- Better TypeScript support
- Improved action state management
- Modern WebSocket-based communication
- Required for Property Inspector features

**Trade-off:** Incomplete TypeScript types, need `@ts-ignore` in places

---

### Why GitHub Actions for Releases?

**Decision:** Automate build and release with GitHub Actions

**Rationale:**
- Consistent build environment (same macOS version)
- Automatically attaches plugin to releases
- No manual packaging errors
- Free for public repos

**Trade-off:** Initial setup complexity, need to learn YAML

---

## Final Tips for AI Assistants

1. **Always verify Swift binary in package** - This was the #1 missed issue
2. **Never commit dist/ folder** - Caused version confusion
3. **Check package structure** - Stream Deck 7.x needs folder in zip
4. **Test locally before GitHub Actions** - Run lint, build, verify
5. **Read error messages carefully** - Stream Deck logs are very helpful
6. **Escape spaces in shell paths** - sudoers, bash scripts, anywhere
7. **SDK 2.0 beta = incomplete types** - Use @ts-ignore when needed
8. **Build order matters** - Swift first, then TypeScript, then package
9. **4-part versions in manifest** - Don't forget the .0
10. **GitHub Actions permissions** - contents:write for releases

---

**Last Updated:** 2025-01-XX (Update this when making significant changes)

**Maintained by:** Claude AI Assistant & Brent Deverman
