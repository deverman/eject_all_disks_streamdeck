#!/bin/bash
#
# Test script to measure actual Jettison ejection time with proper detection
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Jettison Timing Test"
echo "===================================="
echo ""

# Check Jettison is available
if ! command -v osascript &> /dev/null; then
    echo "❌ osascript not available (running on Linux)"
    echo "This test requires macOS to run Jettison"
    exit 1
fi

if ! pgrep -x "Jettison" > /dev/null; then
    echo "❌ Jettison is not running"
    echo "Please start Jettison and run this script again"
    exit 1
fi

# Get current volumes
echo "Current volumes:"
VOLUME_JSON=$("$BINARY_PATH" list --compact 2>&1 | grep -v "SwiftDiskArbitration" | grep -v "DiskSession")
echo "$VOLUME_JSON" | python3 -m json.tool 2>/dev/null
echo ""

INITIAL_COUNT=$("$BINARY_PATH" count)
if [[ $INITIAL_COUNT -eq 0 ]]; then
    echo "⚠️  No volumes to eject"
    exit 1
fi

echo "Will eject $INITIAL_COUNT volume(s)"
echo ""

# Get list of volume paths to monitor
TEMP_JSON=$(mktemp)
echo "$VOLUME_JSON" > "$TEMP_JSON"

VOLUME_PATHS=$(python3 << PYTHON_SCRIPT
import json
with open('$TEMP_JSON', 'r') as f:
    data = json.load(f)
paths = [vol['path'] for vol in data['volumes']]
print(' '.join(f'"{p}"' for p in paths))
PYTHON_SCRIPT
)

rm -f "$TEMP_JSON"

echo "Monitoring paths: $VOLUME_PATHS"
echo ""
echo "Press Enter to start Jettison ejection (this will eject your drives!)..."
read -r
echo ""

# Method 1: Poll volume paths
echo "===================================="
echo "METHOD 1: Poll volume paths"
echo "===================================="
echo ""

START=$(date +%s.%N)

# Trigger Jettison
osascript -e 'tell application "Jettison" to eject all disks' 2>&1

# Poll until all volumes are gone
POLL_COUNT=0
MAX_POLLS=300  # 30 seconds max
VOLUMES_EXIST=true

while [[ $VOLUMES_EXIST == true ]] && [[ $POLL_COUNT -lt $MAX_POLLS ]]; do
    VOLUMES_EXIST=false

    # Check if any volume paths still exist
    for path in $VOLUME_PATHS; do
        # Remove quotes from path
        clean_path=$(echo "$path" | tr -d '"')
        if [[ -d "$clean_path" ]]; then
            VOLUMES_EXIST=true
            break
        fi
    done

    if [[ $VOLUMES_EXIST == true ]]; then
        sleep 0.1
        POLL_COUNT=$((POLL_COUNT + 1))
    fi
done

END=$(date +%s.%N)
DURATION=$(echo "$END - $START" | bc)

echo "Ejection completed in: ${DURATION}s"
echo "Polling iterations: $POLL_COUNT"
echo ""

if [[ $POLL_COUNT -ge $MAX_POLLS ]]; then
    echo "⚠️  Timeout reached - some volumes may still be mounted"
fi

# Verify with our binary
FINAL_COUNT=$("$BINARY_PATH" count)
echo "Verification: $FINAL_COUNT volumes remaining (started with $INITIAL_COUNT)"
echo ""

if [[ $FINAL_COUNT -eq 0 ]]; then
    echo "✅ All volumes successfully ejected in ${DURATION}s"
else
    echo "⚠️  Some volumes still mounted"
fi
echo ""

echo "===================================="
echo "  Analysis"
echo "===================================="
echo ""
echo "If the duration is ~0.05s:"
echo "  → Jettison isn't actually ejecting (or failed)"
echo "  → Check Jettison's UI/preferences"
echo ""
echo "If the duration is several seconds:"
echo "  → Jettison is working correctly"
echo "  → This is the real ejection time to use in benchmarks"
echo ""
echo "For benchmark-suite.sh, use this command:"
echo "  JETTISON_CMD='osascript -e \"tell application \\\"Jettison\\\" to eject all disks\" && while [[ \$($BINARY_PATH count) -gt 0 ]]; do sleep 0.1; done'"
echo ""
