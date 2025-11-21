# Versioning and Release Guide

## Version Numbering

This plugin uses **two version formats**:

### 1. StreamDeck Manifest (4-part version)

**Location**: `org.deverman.ejectalldisks.sdPlugin/manifest.json`

```json
"Version": "1.0.0.0"
```

**Format**: `MAJOR.MINOR.PATCH.BUILD`

- **MAJOR**: Breaking changes or major new features (1.0.0.0 → 2.0.0.0)
- **MINOR**: New features, backwards compatible (1.0.0.0 → 1.1.0.0)
- **PATCH**: Bug fixes, backwards compatible (1.0.0.0 → 1.0.1.0)
- **BUILD**: Usually 0, can increment for quick patches (1.0.0.0 → 1.0.0.1)

### 2. Git Tags (semantic version)

**Format**: `v1.0.0` (without the build number)

This follows semantic versioning and is used for GitHub releases.

## How to Create a Release

### Step 1: Update Version Numbers

**For version 1.0.0 release:**

```bash
# Edit manifest.json - change "Version" from "0.1.0.0" to "1.0.0.0"
# Optionally edit package.json to add matching version
```

### Step 2: Commit Version Bump

```bash
git add org.deverman.ejectalldisks.sdPlugin/manifest.json
git commit -m "Bump version to 1.0.0"
git push
```

### Step 3: Create Git Tag

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release version 1.0.0 - Initial release with disk counting"

# Push tag to GitHub
git push origin v1.0.0
```

### Step 4: Create GitHub Release

**Option A - Via GitHub Web UI:**

1. Go to https://github.com/deverman/eject_all_disks_streamdeck/releases
2. Click "Create a new release"
3. Choose tag: `v1.0.0` (the tag you just pushed)
4. Release title: `v1.0.0 - Initial Release`
5. Description: Write release notes (see template below)
6. Click "Publish release"
7. **GitHub Actions will automatically build and attach the plugin file!**

**Option B - Via GitHub CLI:**

```bash
gh release create v1.0.0 \
  --title "v1.0.0 - Initial Release" \
  --notes "Release notes here"
```

### Step 5: Wait for GitHub Actions

The workflow will automatically:

- Build the plugin
- Package it as `.streamDeckPlugin`
- Attach it to the GitHub release
- Takes ~2-5 minutes on macOS runner

## Release Notes Template

```markdown
## What's New in v1.0.0

### Features

- ✨ Real-time disk count monitoring with 3-second polling
- 🔴 Visual badge showing number of attached external disks
- ⚡ Automatic updates when disks are mounted/unmounted
- 🎨 Animated visual feedback for ejection status
- ⚙️ Customizable button title display

### Technical

- Upgraded to StreamDeck SDK 2.0 beta
- Requires macOS 12+, Stream Deck 6.4+, Node.js 20+

### Installation

Download `org.deverman.ejectalldisks.streamDeckPlugin` and double-click to install.

**Full Changelog**: https://github.com/deverman/eject_all_disks_streamdeck/compare/v0.1.0...v1.0.0
```

## Version History Examples

### Initial Release (1.0.0)

Your first public release with all core features working.

### Feature Release (1.1.0)

```bash
# Update manifest.json: "0.1.0.0" → "1.1.0.0"
git commit -m "Bump version to 1.1.0"
git tag -a v1.1.0 -m "Release v1.1.0 - Add settings panel"
git push origin v1.1.0
# Create GitHub release for v1.1.0
```

Release notes:

```markdown
## What's New in v1.1.0

### New Features

- Added settings panel for customization
- New option to change badge color

### Improvements

- Reduced polling interval from 3s to 2s
- Better error messages

### Bug Fixes

- Fixed issue where badge wouldn't update after sleep
```

### Bug Fix Release (1.0.1)

```bash
# Update manifest.json: "1.0.0.0" → "1.0.1.0"
git commit -m "Bump version to 1.0.1"
git tag -a v1.0.1 -m "Release v1.0.1 - Bug fixes"
git push origin v1.0.1
# Create GitHub release for v1.0.1
```

Release notes:

```markdown
## What's New in v1.0.1

### Bug Fixes

- Fixed timeout cleanup bug causing memory leak
- Fixed badge not disappearing when all disks ejected

No new features - upgrade recommended for stability.
```

### Major Release (2.0.0)

```bash
# Update manifest.json: "1.5.0.0" → "2.0.0.0"
git commit -m "Bump version to 2.0.0"
git tag -a v2.0.0 -m "Release v2.0.0 - Major rewrite"
git push origin v2.0.0
# Create GitHub release for v2.0.0
```

Release notes:

```markdown
## What's New in v2.0.0

### ⚠️ Breaking Changes

- Requires macOS 13+ (dropped support for macOS 12)
- Requires Stream Deck 7.0+

### New Features

- Complete UI redesign
- Support for network drives
- Multi-device support

### Migration Guide

Users on macOS 12 should stay on v1.x releases.
```

## Quick Reference

| Change Type     | Old Version | New Version | Tag      |
| --------------- | ----------- | ----------- | -------- |
| Initial release | 0.1.0.0     | 1.0.0.0     | v1.0.0   |
| Add feature     | 1.0.0.0     | 1.1.0.0     | v1.1.0   |
| Bug fix         | 1.0.0.0     | 1.0.1.0     | v1.0.1   |
| Major change    | 1.9.0.0     | 2.0.0.0     | v2.0.0   |
| Hotfix          | 1.0.1.0     | 1.0.1.1     | v1.0.1.1 |

## Automation Script

Create this helper script `scripts/bump-version.sh`:

```bash
#!/bin/bash

# Usage: ./scripts/bump-version.sh 1.0.0

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  exit 1
fi

VERSION=$1
MANIFEST_VERSION="$VERSION.0"

# Update manifest.json
sed -i '' "s/\"Version\": \".*\"/\"Version\": \"$MANIFEST_VERSION\"/" org.deverman.ejectalldisks.sdPlugin/manifest.json

echo "Updated manifest.json to version $MANIFEST_VERSION"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff"
echo "2. Commit: git commit -am 'Bump version to $VERSION'"
echo "3. Tag: git tag -a v$VERSION -m 'Release v$VERSION'"
echo "4. Push: git push && git push origin v$VERSION"
echo "5. Create GitHub release at: https://github.com/deverman/eject_all_disks_streamdeck/releases/new?tag=v$VERSION"
```

Make executable:

```bash
chmod +x scripts/bump-version.sh
```

Usage:

```bash
./scripts/bump-version.sh 1.0.0
```

## Pre-release Versions

For beta/alpha releases:

```bash
# manifest.json: "1.0.0.0-beta.1" (if SDK supports, otherwise use "0.9.0.0")
git tag -a v1.0.0-beta.1 -m "Beta release"
git push origin v1.0.0-beta.1
# Create GitHub release and mark as "pre-release"
```

## Current Status

- **Current Version**: 0.1.0.0
- **Recommended Next Release**: 1.0.0.0 (initial stable release)
- **Git Tags**: None yet

## When to Release

- **1.0.0**: When ready for first public release (you're ready now!)
- **1.0.x**: Bug fixes to 1.0.0
- **1.x.0**: New features (e.g., network drive support, custom colors)
- **2.0.0**: Breaking changes (e.g., dropping macOS 12 support, API changes)
