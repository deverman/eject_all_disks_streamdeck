#!/bin/bash

# Bump version script for Eject All Disks Stream Deck plugin
# Usage: ./scripts/bump-version.sh 1.0.0

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.0.0"
  echo ""
  echo "Version format: MAJOR.MINOR.PATCH"
  echo "  MAJOR: Breaking changes (1.0.0 → 2.0.0)"
  echo "  MINOR: New features (1.0.0 → 1.1.0)"
  echo "  PATCH: Bug fixes (1.0.0 → 1.0.1)"
  exit 1
fi

VERSION=$1
MANIFEST_VERSION="$VERSION.0"

# Validate version format
if ! [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid version format. Use MAJOR.MINOR.PATCH (e.g., 1.0.0)"
  exit 1
fi

echo "🔄 Bumping version to $VERSION..."
echo ""

# Update manifest.json (macOS compatible sed)
# Note: We need to match only the top-level "Version" field (after "Name")
# and not the Nodejs "Version" field, so we use a more specific pattern
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "2,5s/\"Version\": \"[^\"]*\"/\"Version\": \"$MANIFEST_VERSION\"/" org.deverman.ejectalldisks.sdPlugin/manifest.json
else
  sed -i "2,5s/\"Version\": \"[^\"]*\"/\"Version\": \"$MANIFEST_VERSION\"/" org.deverman.ejectalldisks.sdPlugin/manifest.json
fi

echo "✅ Updated manifest.json to version $MANIFEST_VERSION"
echo ""

# Show the diff
git diff org.deverman.ejectalldisks.sdPlugin/manifest.json

echo ""
echo "📝 Next steps:"
echo ""
echo "1️⃣  Review changes above"
echo "2️⃣  Commit: git add . && git commit -m 'Bump version to $VERSION'"
echo "3️⃣  Tag: git tag -a v$VERSION -m 'Release v$VERSION'"
echo "4️⃣  Push: git push && git push origin v$VERSION"
echo "5️⃣  Create release: https://github.com/deverman/eject_all_disks_streamdeck/releases/new?tag=v$VERSION"
echo ""
echo "💡 Tip: GitHub Actions will automatically build and attach the plugin to the release!"
