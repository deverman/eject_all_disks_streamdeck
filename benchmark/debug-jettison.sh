#!/bin/bash
#
# Debug script to understand why Jettison benchmark shows 0.05s
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Jettison Detection Debug"
echo "===================================="
echo ""

# Step 1: Check what volumes we have
echo "Step 1: Current volumes from our binary"
echo "========================================"
VOLUME_JSON=$("$BINARY_PATH" list --compact 2>&1 | grep -v "SwiftDiskArbitration" | grep -v "DiskSession")
echo "$VOLUME_JSON" | python3 -m json.tool 2>/dev/null || echo "$VOLUME_JSON"
echo ""

# Step 2: Check what diskutil list shows
echo "Step 2: What does 'diskutil list' show?"
echo "========================================"
diskutil list
echo ""

# Step 3: Test the grep pattern
echo "Step 3: Testing grep pattern 'external, physical'"
echo "=================================================="
if diskutil list | grep -q 'external, physical'; then
    echo "✅ Pattern MATCHES - found drives with 'external, physical'"
    echo ""
    echo "Matching lines:"
    diskutil list | grep 'external, physical'
else
    echo "❌ Pattern DOES NOT MATCH - no drives with 'external, physical'"
    echo ""
    echo "This explains why the polling loop exits immediately!"
fi
echo ""

# Step 4: Check each volume path
echo "Step 4: Alternative detection - check volume paths exist"
echo "========================================================="
TEMP_JSON=$(mktemp)
echo "$VOLUME_JSON" > "$TEMP_JSON"

python3 << PYTHON_SCRIPT
import json

with open('$TEMP_JSON', 'r') as f:
    data = json.load(f)

print(f"We have {data['count']} volumes to track:")
for vol in data['volumes']:
    print(f"  - {vol['name']}: {vol['path']}")

print()
print("Detection methods:")
print("  1. Check if /Volumes/{name} exists")
print("  2. Check 'diskutil info {bsdName}' returns valid data")
print("  3. Poll our own binary's count")
PYTHON_SCRIPT

rm -f "$TEMP_JSON"
echo ""

# Step 5: Test Jettison command
echo "Step 5: Does Jettison AppleScript work?"
echo "========================================"
echo "Testing: osascript -e 'tell application \"Jettison\" to eject all disks'"
echo ""

if ! command -v osascript &> /dev/null; then
    echo "❌ osascript not available (running on Linux)"
    echo "Cannot test Jettison AppleScript"
else
    if pgrep -x "Jettison" > /dev/null; then
        echo "✅ Jettison is running"
        echo ""
        echo "Attempting to trigger eject (this will actually eject your drives!):"
        echo "Press Ctrl+C to cancel, or Enter to continue..."
        read -r

        START=$(date +%s.%N)
        osascript -e 'tell application "Jettison" to eject all disks' 2>&1
        END=$(date +%s.%N)
        APPLESCRIPT_TIME=$(echo "$END - $START" | bc)

        echo ""
        echo "AppleScript completed in: ${APPLESCRIPT_TIME}s"
        echo ""
        echo "If this was ~0.05s, Jettison might be returning before ejection completes"
    else
        echo "❌ Jettison is not running"
        echo ""
        echo "Please start Jettison and run this script again"
    fi
fi
echo ""

# Step 6: Recommend fix
echo "===================================="
echo "  Recommendations"
echo "===================================="
echo ""
echo "Based on the detection test above:"
echo ""
echo "If 'external, physical' doesn't match:"
echo "  → Use volume path detection instead:"
echo "     while [[ -d /Volumes/Caoshu1 ]] || [[ -d /Volumes/Caoshu2 ]] || [[ -d /Volumes/Kaishu1 ]]; do"
echo "       sleep 0.1"
echo "     done"
echo ""
echo "  → Or use our binary's count:"
echo "     while [[ \$($BINARY_PATH count) -gt 0 ]]; do"
echo "       sleep 0.1"
echo "     done"
echo ""
echo "If Jettison AppleScript returns immediately (~0.05s):"
echo "  → Jettison might eject asynchronously"
echo "  → We need to poll for completion, not assume the command waits"
echo ""
