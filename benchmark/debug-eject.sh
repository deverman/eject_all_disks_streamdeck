#!/bin/bash
#
# Debug script to test ejection performance with detailed timing
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Disk Ejection Debug Test"
echo "===================================="
echo ""

# Check if binary exists
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "❌ Binary not found. Please build first:"
    echo "  cd ../swift && ./build.sh"
    exit 1
fi

# Count volumes
VOLUME_COUNT=$("$BINARY_PATH" count)
echo "Found $VOLUME_COUNT ejectable volume(s)"
echo ""

if [[ $VOLUME_COUNT -eq 0 ]]; then
    echo "⚠️  No ejectable volumes found."
    echo ""
    echo "Options:"
    echo "  1. Mount a real USB drive (recommended for accurate testing)"
    echo "  2. Create test disk images:"
    echo "     hdiutil create -size 10m -fs HFS+ -volname TestDisk /tmp/test.dmg"
    echo "     hdiutil attach /tmp/test.dmg"
    exit 1
fi

# Show volumes
echo "Volumes to eject:"
"$BINARY_PATH" list --compact | python3 -m json.tool 2>/dev/null || "$BINARY_PATH" list --compact
echo ""

# Test 1: Native API with debug output
echo "===================================="
echo "TEST: Native DiskArbitration API"
echo "===================================="
echo ""
echo "Running eject with debug output enabled..."
echo "Watch for timing information from [SwiftDiskArbitration]"
echo ""
echo "---"

# Time the operation
START=$(date +%s.%N)
OUTPUT=$("$BINARY_PATH" eject --compact 2>&1)
END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)

echo "$OUTPUT"
echo "---"
echo ""
echo "Total measured time: ${DURATION}s"
echo ""

# Parse JSON to check success
if echo "$OUTPUT" | grep -q '"totalCount"'; then
    TOTAL=$(echo "$OUTPUT" | grep -o '"totalCount":[0-9]*' | grep -o '[0-9]*')
    SUCCESS=$(echo "$OUTPUT" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
    FAILED=$(echo "$OUTPUT" | grep -o '"failedCount":[0-9]*' | grep -o '[0-9]*')
    JSON_DURATION=$(echo "$OUTPUT" | grep -o '"totalDuration":[0-9.]*' | grep -o '[0-9.]*')

    echo "Results:"
    echo "  Success: $SUCCESS/$TOTAL"
    echo "  Failed: $FAILED"
    echo "  JSON Duration: ${JSON_DURATION}s"
    echo ""

    # Check for permission errors
    if echo "$OUTPUT" | grep -q "Not privileged"; then
        echo "⚠️  PERMISSION ERROR DETECTED"
        echo ""
        echo "The volumes require administrator privileges to eject."
        echo ""
        echo "Solutions:"
        echo "  1. Run with sudo: sudo $0"
        echo "  2. Test with real USB drives (they usually don't need sudo)"
        echo "  3. Install privileged helper:"
        echo "     cd ../org.deverman.ejectalldisks.sdPlugin/bin"
        echo "     sudo ./install-eject-privileges.sh"
        echo ""
    fi

    # Show timing analysis
    if (( $(echo "$JSON_DURATION < 0.5" | bc -l) )); then
        echo "✅ PERFORMANCE: Excellent! Ejection attempted in ${JSON_DURATION}s"
        echo "   This confirms your code is FAST (not the 11s we saw with disk images)"
        echo ""
    elif (( $(echo "$JSON_DURATION > 5" | bc -l) )); then
        echo "⚠️  PERFORMANCE: Slow (${JSON_DURATION}s)"
        echo "   Check if these are disk images or network drives"
        echo ""
    fi
fi

# Analysis
echo "===================================="
echo "  Analysis"
echo "===================================="
echo ""
echo "Look for timing patterns in the debug output above:"
echo ""
echo "1. Unmount callback timing:"
echo "   - If unmount takes 10+ seconds → macOS is slow to unmount"
echo "   - Likely causes: Spotlight indexing, disk syncing, system processes"
echo ""
echo "2. Eject callback timing:"
echo "   - If eject is fast but total is slow → unmount is the bottleneck"
echo "   - If both are slow → macOS system issue"
echo ""
echo "3. Disk type matters:"
echo "   - Real USB drives: Usually fast (0.1s - 1s)"
echo "   - Disk images (hdiutil): Often slow (10s+) due to macOS overhead"
echo "   - Network drives: Can be very slow"
echo ""
echo "Recommendations:"
echo "  - Test with real USB drive for accurate benchmarks"
echo "  - Disable Spotlight: sudo mdutil -a -i off"
echo "  - Check for processes using the disk: lsof +f -- /Volumes/YourDisk"
echo ""
