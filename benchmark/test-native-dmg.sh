#!/bin/bash
#
# Test Native API ejection with disk images to debug benchmark failure
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Native API + DMG Debug Test"
echo "===================================="
echo ""

# Create 3 small test disk images
echo "Step 1: Creating 3 test disk images..."
DMG_PATHS=()
for i in 1 2 3; do
    DMG_PATH="/tmp/TestDisk${i}_debug.dmg"

    # Remove if exists
    if [[ -f "$DMG_PATH" ]]; then
        hdiutil detach "/Volumes/TestDisk${i}" 2>/dev/null || true
        rm -f "$DMG_PATH"
    fi

    # Create new DMG
    hdiutil create -size 10m -fs HFS+ -volname "TestDisk${i}" "$DMG_PATH" >/dev/null 2>&1

    # Mount it
    hdiutil attach "$DMG_PATH" >/dev/null 2>&1

    # Disable Spotlight indexing to prevent mds from blocking ejection
    touch "/Volumes/TestDisk${i}/.metadata_never_index"

    DMG_PATHS+=("$DMG_PATH")
    echo "  Created and mounted: TestDisk${i}"
done
echo ""

# Wait for mounts to stabilize
sleep 2

# List what we have
echo "Step 2: Checking mounted volumes..."
VOLUME_LIST=$("$BINARY_PATH" list --compact 2>&1 | grep -v "SwiftDiskArbitration")
echo "$VOLUME_LIST" | python3 -m json.tool
echo ""

VOLUME_COUNT=$("$BINARY_PATH" count)
echo "Total volumes: $VOLUME_COUNT"
echo ""

# Test with Native API + verbose (Spotlight disabled via .metadata_never_index)
echo "Step 3: Ejecting with Native API (verbose)..."
echo "Running: sudo $BINARY_PATH eject --verbose"
echo "(Spotlight indexing disabled to prevent mds from blocking ejection)"
echo ""

sudo "$BINARY_PATH" eject --verbose 2>&1 | tee /tmp/native_debug.log

echo ""
echo "Step 4: Analysis..."

# Check how many were ejected
REMAINING=$("$BINARY_PATH" count)
EJECTED=$((VOLUME_COUNT - REMAINING))

echo "  Started with: $VOLUME_COUNT volumes"
echo "  Ejected: $EJECTED volumes"
echo "  Remaining: $REMAINING volumes"
echo ""

if [[ $REMAINING -gt 0 ]]; then
    echo "⚠️  Some volumes were NOT ejected!"
    echo ""
    echo "Remaining volumes:"
    "$BINARY_PATH" list --compact | python3 -m json.tool
    echo ""
fi

# Extract any errors from the log
if grep -q "dissenter" /tmp/native_debug.log; then
    echo "Errors found in ejection:"
    grep "dissenter" /tmp/native_debug.log
    echo ""
fi

# Now test with diskutil for comparison
echo "Step 5: Remounting all disk images..."
for dmg in "${DMG_PATHS[@]}"; do
    hdiutil attach "$dmg" >/dev/null 2>&1
    # Disable Spotlight indexing to prevent mds from blocking ejection
    local volname=$(basename "$dmg" .dmg | sed 's/_debug//')
    touch "/Volumes/${volname}/.metadata_never_index" 2>/dev/null || true
done
sleep 2

REMOUNTED=$("$BINARY_PATH" count)
echo "  Remounted: $REMOUNTED volumes"
echo ""

echo "Step 6: Ejecting with diskutil for comparison..."
echo "Running: sudo $BINARY_PATH eject --use-diskutil --compact"
echo ""

sudo "$BINARY_PATH" eject --use-diskutil --compact 2>&1 | python3 -m json.tool

echo ""

REMAINING_DISKUTIL=$("$BINARY_PATH" count)
EJECTED_DISKUTIL=$((REMOUNTED - REMAINING_DISKUTIL))

echo "  Ejected: $EJECTED_DISKUTIL volumes"
echo "  Remaining: $REMAINING_DISKUTIL volumes"
echo ""

# Cleanup
echo "Cleaning up..."
for dmg in "${DMG_PATHS[@]}"; do
    hdiutil detach "/Volumes/$(basename "$dmg" .dmg | sed 's/_debug//')" 2>/dev/null || true
    rm -f "$dmg"
done

echo ""
echo "===================================="
echo "  Summary"
echo "===================================="
echo ""
echo "Native API:  Ejected $EJECTED/$VOLUME_COUNT"
echo "diskutil:    Ejected $EJECTED_DISKUTIL/$REMOUNTED"
echo ""

if [[ $EJECTED -lt $VOLUME_COUNT ]]; then
    echo "❌ Native API failed to eject all volumes"
    echo ""
    echo "Check /tmp/native_debug.log for details"
else
    echo "✅ Both methods worked correctly"
fi
echo ""
