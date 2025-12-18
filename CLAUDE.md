# CLAUDE.md - AI Assistant Guide for Stream Deck Plugin Development

**Generic Guide for Stream Deck + Swift Binary Plugins**

This document provides architectural guidance and critical gotchas for AI assistants (or developers) working on Stream Deck plugins that integrate Swift command-line binaries.

**Use Case:** This guide is designed for plugins that need native macOS functionality (via Swift frameworks) called from a TypeScript/Node.js Stream Deck plugin.

**Examples:** DiskArbitration (disk management), IOKit (hardware), Core Audio (audio devices), IOBluetooth (Bluetooth), Security (keychain)

> **📖 How to use this guide:**
> This is a **generic template** with placeholders like `com.yourname.pluginname` and `swift-binary`.
> See [Adapting This Guide to Your Project](#adapting-this-guide-to-your-project) at the bottom for how to customize it.
> The gotchas and architectural patterns apply to ANY Stream Deck plugin with Swift integration.

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
│  └─> Loads: com.yourname.pluginname.sdPlugin    │
│       ├─> Node.js 20 Runtime                    │
│       │    └─> bin/plugin.js (compiled TS)      │
│       └─> Swift Binary                          │
│            └─> bin/swift-binary (native)        │
└─────────────────────────────────────────────────┘
```

**Technology Stack:**
- **Frontend:** TypeScript → JavaScript (via Rollup)
- **Native Binary:** Swift → Compiled executable
- **SDK:** Stream Deck SDK 2.0 (beta) - TypeScript types may be incomplete
- **Platform:** macOS only (when using macOS-specific Swift frameworks)
- **Package Format:** `.streamDeckPlugin` (renamed .zip file)

**Build Order (CRITICAL):**
1. Swift binary (`npm run build:swift`) → `bin/swift-binary`
2. TypeScript code (`npm run build`) → `bin/plugin.js`
3. Package plugin (zip) → `dist/com.yourname.pluginname.streamDeckPlugin`

> **This Project Example:** We use Swift to access macOS DiskArbitration framework for fast parallel disk ejection (~6x faster than shell commands). Your use case might be Core Audio, IOKit, or other macOS-specific functionality.

---

## Critical Gotchas - Read This First

### 🚨 Top 10 Issues That WILL Break Your Build

#### 1. **Stream Deck 7.x Package Structure**
```bash
# ❌ WRONG - Files at root
cd com.yourname.pluginname.sdPlugin
zip -r ../plugin.streamDeckPlugin .

# ✅ CORRECT - Include folder name
zip -r plugin.streamDeckPlugin com.yourname.pluginname.sdPlugin
```

**Why:** Stream Deck 7.x expects the .streamDeckPlugin file to contain a folder with the plugin files inside it, not files at the root. Installing a plugin with files at root gives: `"Error: No plugin found in bundle"`

**Location:** `.github/workflows/main.yml` packaging step

**How to verify:**
```bash
unzip -l plugin.streamDeckPlugin | head -5
# Should show: com.yourname.pluginname.sdPlugin/manifest.json
# NOT: manifest.json
```

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
    if [ ! -f "com.yourname.pluginname.sdPlugin/bin/swift-binary" ]; then
      echo "Error: Swift binary missing!"
      exit 1
    fi
```

**Why:** If you built the TypeScript/Node.js plugin before the Swift binary existed, and then committed the packaged `.streamDeckPlugin` file to git, the old package (without the Swift binary) will be what gets distributed. Even if you later build the Swift binary locally, the committed package won't include it.

**Symptoms:** Plugin installs but Swift-dependent features don't work (e.g., no dynamic state updates, native operations fail)

**The Real Issue:** This is often combined with **Gotcha #5** (committed build artifacts). The Swift binary was missing from an old committed package, not from the current build.

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

#### 9. **Sudoers Path Escaping (If Using Passwordless Sudo)**
```bash
# ❌ WRONG - Spaces not escaped
/Users/user/Library/Application Support/com.elgato.StreamDeck/...

# ✅ CORRECT - Escape spaces with backslash
/Users/user/Library/Application\ Support/com.elgato.StreamDeck/...
```

**Why:** The sudoers file format requires escaped spaces in paths. Stream Deck plugins are installed in `~/Library/Application Support/com.elgato.StreamDeck/Plugins/` which contains spaces. If your setup script creates a sudoers rule without escaping these spaces, `sudo -n` will fail to match the path and always ask for password.

**Fix in privilege setup script:**
```bash
# Escape spaces in the binary path for sudoers format
ESCAPED_BINARY=$(echo "$SWIFT_BINARY_PATH" | sed 's/ /\\ /g')
SUDOERS_RULE="$CURRENT_USER ALL=(ALL) NOPASSWD: $ESCAPED_BINARY *"
```

**Location:** `com.yourname.pluginname.sdPlugin/bin/install-privileges.sh` (or similar setup script)

**Symptom:** Privilege setup script runs successfully but status check still shows "not configured" or sudo still asks for password

**Note:** Only relevant if your Swift binary needs elevated privileges (sudo) to access system resources

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
npm run build:swift  # Compiles Swift → bin/swift-binary
npm run build        # Compiles TypeScript → bin/plugin.js
```

**Output:**
```
com.yourname.pluginname.sdPlugin/
└── bin/
    ├── plugin.js       # From TypeScript
    └── swift-binary    # From Swift
```

**package.json scripts example:**
```json
{
  "scripts": {
    "build:swift": "swift build -c release --package-path swift && cp swift/.build/release/swift-binary com.yourname.pluginname.sdPlugin/bin/",
    "build": "rollup -c",
    "watch": "streamdeck dev"
  }
}
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
zip -r dist/com.yourname.pluginname.streamDeckPlugin \
  com.yourname.pluginname.sdPlugin \
  -x "*.DS_Store" \
  -x "*/logs/*" \
  -x "*.log" \
  -x "*/.git/*" \
  -x "*/.gitignore" \
  -x "*/pi/*"
```

**Critical:** Include the folder name in the zip, not just its contents (see Gotcha #1)

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

# ✅ Verify binary exists (CRITICAL - catches missing binary before packaging)
- name: Verify build output
  run: |
    if [ ! -f "com.yourname.pluginname.sdPlugin/bin/swift-binary" ]; then
      echo "Error: Swift binary not found after build"
      exit 1
    fi
    if [ ! -f "com.yourname.pluginname.sdPlugin/bin/plugin.js" ]; then
      echo "Error: plugin.js not found after build"
      exit 1
    fi
```

#### 4. Package
```yaml
- name: Package plugin
  run: |
    mkdir -p dist
    zip -r dist/com.yourname.pluginname.streamDeckPlugin \
      com.yourname.pluginname.sdPlugin \
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
com.yourname.pluginname.sdPlugin/
├── manifest.json          # Plugin metadata - CRITICAL
├── bin/                   # Compiled output
│   ├── plugin.js          # From TypeScript build
│   ├── swift-binary       # From Swift build
│   └── install-privileges.sh  # Optional: Privilege setup script (if using sudo)
├── ui/                    # Property Inspector (optional)
│   └── property-inspector.html
├── imgs/                  # Icons
│   ├── actions/
│   │   ├── actionname/   # SVG/PNG icons for different states
│   └── plugin/           # Plugin icon
└── logs/                  # Runtime logs (auto-created, excluded from package)
```

### manifest.json - Critical Fields

```json
{
  "Name": "Your Plugin Name",
  "Version": "1.0.0.0",  // 4-part format (CRITICAL - see Gotcha #6)
  "Author": "Your Name",
  "UUID": "com.yourname.pluginname",  // Must match folder name pattern

  "Nodejs": {
    "Version": "20"
    // ❌ DON'T add "Debug": "enabled" here (see Gotcha #7)
    // It's not a valid field and will break installation
  },

  "Actions": [
    {
      "UUID": "com.yourname.pluginname.actionname",
      "Name": "Action Display Name",
      "Icon": "imgs/actions/actionname/icon",  // Without extension
      "States": [
        {
          "Image": "imgs/actions/actionname/icon"
        }
      ],
      "PropertyInspectorPath": "ui/property-inspector.html"  // Optional
    }
  ],

  "OS": [
    {
      "Platform": "mac",
      "MinimumVersion": "12.0"  // Adjust based on your Swift framework requirements
    }
  ],

  "SDKVersion": 2,
  "Software": {
    "MinimumVersion": "6.4"
  }
}
```

**Validation:**
- `UUID` must match plugin folder name pattern (e.g., `com.yourname.pluginname` → `com.yourname.pluginname.sdPlugin`)
- `Version` must be 4-part format: `MAJOR.MINOR.PATCH.BUILD` (e.g., `1.0.0.0`)
- Icon paths are without extension (.png/.svg auto-detected)
- `SDKVersion: 2` for SDK 2.0 beta
- `Nodejs.Version` should stay `"20"` - don't modify when bumping plugin version (see Gotcha #6)

---

## Swift Binary Integration

### Purpose
Swift binaries allow you to access native macOS frameworks that aren't available in Node.js, such as:
- **DiskArbitration** - Disk management and ejection
- **IOKit** - Hardware and device interaction
- **Core Audio** - Audio device control
- **IOBluetooth** - Bluetooth device management
- **Security** - Keychain and certificate access

> **This Project Example:** We use Swift to access the DiskArbitration framework for parallel disk ejection (~6x faster than spawning shell commands).

### Build Configuration

**File:** `swift/Package.swift`
```swift
let package = Package(
    name: "YourBinaryName",
    platforms: [
        .macOS(.v12)  // Minimum macOS version (adjust as needed)
    ],
    products: [
        .executable(
            name: "swift-binary",  // Output binary name
            targets: ["YourBinaryName"]
        )
    ],
    targets: [
        .executableTarget(
            name: "YourBinaryName",
            dependencies: []
        )
    ]
)
```

**Build script in package.json:**
```json
{
  "scripts": {
    "build:swift": "swift build -c release --package-path swift && cp swift/.build/release/swift-binary com.yourname.pluginname.sdPlugin/bin/"
  }
}
```

### Swift → TypeScript Integration

**TypeScript calls Swift binary:**
```typescript
import { spawn } from 'child_process';
import * as path from 'path';

const swiftBinary = path.join(__dirname, 'swift-binary');

// Example: Call binary with arguments
const process = spawn(swiftBinary, ['command', 'arg1', 'arg2']);

process.stdout.on('data', (data) => {
  console.log(`Output: ${data}`);
});

process.stderr.on('data', (data) => {
  console.error(`Error: ${data}`);
});

process.on('close', (code) => {
  console.log(`Exited with code: ${code}`);
});
```

**If your binary needs sudo privileges:**
```typescript
// Use 'sudo -n' for passwordless execution (requires sudoers setup - see Gotcha #9)
const process = spawn('sudo', ['-n', swiftBinary, 'command', 'arg1']);
```

**Important:**
- Always use absolute path to binary (via `path.join(__dirname, 'swift-binary')`)
- Handle both stdout and stderr streams
- Check exit codes for error handling
- For sudo operations, set up sudoers with escaped paths (Gotcha #9)

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
MANIFEST_VERSION="${VERSION}.0"  # Add .0 for Stream Deck 4-part format

# ✅ CRITICAL: Only update plugin Version, NOT Nodejs.Version
# Use line range to target only the top-level Version field
# Adjust range based on your manifest.json structure (typically lines 2-5)
sed -i '' "2,5s/\"Version\": \"[^\"]*\"/\"Version\": \"$MANIFEST_VERSION\"/" \
  com.yourname.pluginname.sdPlugin/manifest.json

echo "✅ Updated manifest.json to version $MANIFEST_VERSION"
```

**Why the line range (2,5):** Without it, sed would match BOTH occurrences of `"Version"`:
1. Line 3: `"Version": "1.0.0.0"` ✅ (what we want to change)
2. Line 8: `"Nodejs": {"Version": "20"}` ❌ (must NOT change)

Without the line range, sed would change `"Nodejs": {"Version": "20"}` to `"Nodejs": {"Version": "2.0.2.0"}`, breaking the plugin.

**Verify your line numbers:**
```bash
cat -n com.yourname.pluginname.sdPlugin/manifest.json | head -10
```
Adjust the `2,5` range to match where your top-level `"Version"` field appears.

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
vim src/actions/your-action.ts

# 2. Lint and format
npm run lint:fix

# 3. Build
npm run build

# 4. Test in Stream Deck
npx streamdeck restart com.yourname.pluginname
```

### Task 2: Fix Swift Binary
```bash
# 1. Make changes in swift/
vim swift/Sources/YourBinary.swift

# 2. Build Swift binary
npm run build:swift

# 3. Verify binary exists and is executable
ls -lh com.yourname.pluginname.sdPlugin/bin/swift-binary
chmod +x com.yourname.pluginname.sdPlugin/bin/swift-binary

# 4. Test in Stream Deck
npx streamdeck restart com.yourname.pluginname
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
tail -f ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/com.yourname.pluginname.sdPlugin/logs/*.log

# 3. Test package structure (CRITICAL - see Gotcha #1)
unzip -l dist/plugin.streamDeckPlugin | head -20
# Should show: com.yourname.pluginname.sdPlugin/manifest.json
# NOT: manifest.json

# 4. Verify Swift binary is in package
unzip -l dist/plugin.streamDeckPlugin | grep swift-binary
# Should show: com.yourname.pluginname.sdPlugin/bin/swift-binary

# 5. Remove quarantine (if needed on macOS)
xattr -rc dist/plugin.streamDeckPlugin
```

### Task 5: Test Sudoers Setup (If Using Passwordless Sudo)
```bash
# 1. Check if sudoers file exists
ls -l /etc/sudoers.d/your-plugin-name

# 2. View sudoers rule
sudo cat /etc/sudoers.d/your-plugin-name

# 3. Verify path has escaped spaces (CRITICAL - see Gotcha #9)
# Should show: /Users/user/Library/Application\ Support/com.elgato.StreamDeck/...
# NOT: /Users/user/Library/Application Support/com.elgato.StreamDeck/...

# 4. Test passwordless sudo
sudo -n ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/com.yourname.pluginname.sdPlugin/bin/swift-binary --version
# Should NOT ask for password

# 5. If it asks for password, delete and recreate with escaped spaces
sudo rm /etc/sudoers.d/your-plugin-name
# Then re-run your privilege setup script
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

### Issue: Swift Binary Features Not Working

**Symptom:** Plugin installs but Swift-dependent features don't work (e.g., dynamic state updates, badge counts, native operations fail)

**Root Cause:** This is almost always because the Swift binary is **missing from the packaged .streamDeckPlugin file**, usually due to **committed build artifacts** (Gotcha #5).

**Diagnosis:**
1. **Check if Swift binary is in the package**
   ```bash
   unzip -l dist/plugin.streamDeckPlugin | grep swift-binary
   # Should show: com.yourname.pluginname.sdPlugin/bin/swift-binary
   ```

2. **If missing, check git history**
   ```bash
   git log --all --full-history -- dist/
   # If you see commits here, you committed build artifacts
   ```

**Fixes:**
1. **Remove committed build artifacts**
   ```bash
   git rm -r dist/
   echo "dist/" >> .gitignore
   git commit -m "Remove committed build artifacts"
   ```

2. **Rebuild with Swift binary FIRST**
   ```bash
   npm run build:swift
   ls -lh com.yourname.pluginname.sdPlugin/bin/swift-binary
   # Should show a file (size depends on your binary)
   npm run build
   ```

3. **Verify binary is executable**
   ```bash
   chmod +x com.yourname.pluginname.sdPlugin/bin/swift-binary
   ```

4. **Package and verify**
   ```bash
   # Package (following Gotcha #1 - include folder name)
   zip -r dist/plugin.streamDeckPlugin com.yourname.pluginname.sdPlugin

   # Verify Swift binary is in package
   unzip -l dist/plugin.streamDeckPlugin | grep swift-binary
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

**When to use Swift binaries:**
- Need access to macOS-specific frameworks (DiskArbitration, IOKit, Core Audio, etc.)
- Performance-critical operations that benefit from native code
- Hardware interaction not available via Node.js
- Need to call private/undocumented macOS APIs

**Advantages:**
- Direct access to macOS frameworks not available in Node.js
- Significantly faster than spawning shell commands repeatedly
- Can use Swift concurrency for parallel operations
- Type-safe, compiled code with better error handling

**Trade-offs:**
- macOS only (Swift binaries won't run on Windows)
- Adds build complexity (two separate build pipelines)
- Harder to debug than pure JavaScript
- Requires macOS for development and CI/CD

**This Project Example:** We use Swift to access DiskArbitration framework for parallel disk ejection (~6x faster than spawning `diskutil` shell commands).

---

### Why SDK 2.0 Beta?

**Decision:** Use Stream Deck SDK 2.0 (beta) instead of stable 1.x

**Advantages:**
- Better TypeScript support and type definitions
- Improved action state management
- Modern WebSocket-based communication
- Better Property Inspector integration
- Simplified API surface

**Trade-offs:**
- Incomplete TypeScript types (need `@ts-ignore` workarounds - see Gotcha #10)
- Beta software may have breaking changes
- Less documentation and community support
- Some APIs exist at runtime but not in type definitions

**Recommendation:** Use SDK 2.0 for new projects. The TypeScript improvements outweigh the beta limitations.

---

### Why GitHub Actions for Releases?

**Decision:** Automate build and release with GitHub Actions

**Advantages:**
- Consistent build environment (everyone uses same macOS version, Swift version, Node version)
- Automatically builds and attaches `.streamDeckPlugin` to releases
- Eliminates manual packaging errors
- Catches build errors before release
- Free for public repos
- Built-in integration with GitHub Releases

**Trade-offs:**
- Initial setup complexity (learn YAML syntax)
- Debugging workflow failures can be slow (push → wait → check logs)
- macOS runners can be slow to start
- Limited to 6-hour job timeout

**Recommendation:** Always use CI/CD for releases. Manual packaging inevitably leads to errors (see all 10 gotchas).

---

## Final Tips for AI Assistants

When working on a Stream Deck plugin with Swift binaries, prioritize these issues:

1. **Always verify Swift binary in package** (#1 most common issue)
   - Check with: `unzip -l dist/plugin.streamDeckPlugin | grep swift-binary`
   - If missing, almost always due to committed build artifacts (Gotcha #5)

2. **Never commit dist/ folder** (Gotcha #5)
   - Causes version confusion and missing binaries
   - Always add to .gitignore

3. **Check package structure** (Gotcha #1)
   - Stream Deck 7.x needs folder name in zip
   - Verify with: `unzip -l plugin.streamDeckPlugin | head -5`

4. **Test locally before pushing to GitHub Actions**
   - Run `npm run lint:fix` (avoid formatting failures)
   - Run `npm run build:swift && npm run build` (test build order)
   - Verify both binaries exist before packaging

5. **Read error messages carefully**
   - Stream Deck logs: `~/Library/Logs/ElgatoStreamDeck/StreamDeck0.log`
   - "No plugin found in bundle" = wrong package structure (Gotcha #1)
   - Version mismatch = committed build artifacts (Gotcha #5)

6. **Escape spaces in shell paths** (Gotcha #9)
   - sudoers files require: `Application\ Support`
   - Use: `sed 's/ /\\ /g'` to escape

7. **SDK 2.0 beta = incomplete types** (Gotcha #10)
   - Use `@ts-ignore` for runtime APIs not in type definitions
   - Don't try to "fix" by using non-existent APIs

8. **Build order is critical** (Gotcha #2)
   - Swift FIRST, then TypeScript, then package
   - Add verification steps in CI/CD

9. **4-part versions in manifest.json** (Gotcha #6)
   - Manifest uses: `"1.0.0.0"` (4-part)
   - Git tags use: `v1.0.0` (3-part)
   - Don't modify `Nodejs.Version` when bumping

10. **GitHub Actions needs permissions** (Gotcha #3)
    - Add `permissions: contents: write` for releases
    - Use modern actions (Gotcha #4)

---

## Adapting This Guide to Your Project

This guide uses placeholders like `com.yourname.pluginname` and `swift-binary`. To adapt it to your specific project:

**Find and replace these placeholders:**
- `com.yourname.pluginname` → your plugin UUID (e.g., `com.acme.volumecontrol`)
- `swift-binary` → your binary name (e.g., `audio-controller`)
- `YourBinaryName` → your Swift package name (e.g., `AudioController`)

**Update paths in scripts:**
- `com.yourname.pluginname.sdPlugin/` → your actual plugin folder
- `swift/.build/release/swift-binary` → your actual Swift build output

**Customize for your use case:**
- Replace "This Project Example" sections with your specific Swift framework usage
- Update manifest.json template with your actual actions and UUIDs
- Adjust macOS version requirements based on frameworks you use

---

**Last Updated:** 2025-01-18 (Update this when making significant changes)

**Maintained by:** Claude AI Assistant & Brent Deverman
