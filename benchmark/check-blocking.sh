#!/bin/bash
#
# Check what processes might be blocking disk ejection
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Checking Blocking Processes"
echo "===================================="
echo ""

# Get volume list
RAW_OUTPUT=$("$BINARY_PATH" list --compact 2>&1)

# Filter out debug lines to get clean JSON
VOLUMES=$(echo "$RAW_OUTPUT" | grep -v "SwiftDiskArbitration" | grep -v "DiskSession")

# Check if we got valid JSON
if ! echo "$VOLUMES" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    echo "❌ Failed to get volume list from binary"
    echo ""
    echo "Raw output was:"
    echo "$RAW_OUTPUT"
    echo ""
    echo "Filtered JSON:"
    echo "$VOLUMES"
    exit 1
fi

# Check if we have any volumes
COUNT=$(echo "$VOLUMES" | python3 -c "import sys, json; print(json.load(sys.stdin)['count'])")
if [[ "$COUNT" == "0" ]]; then
    echo "No volumes found to check"
    exit 0
fi

echo "Checking $COUNT volume(s) for processes with open files..."
echo ""

# Parse volume paths and check each one
echo "$VOLUMES" | python3 << 'PYTHON_SCRIPT'
import sys
import json
import subprocess

data = json.load(sys.stdin)

for vol in data['volumes']:
    name = vol['name']
    path = vol['path']

    print(f"{'='*60}")
    print(f"Volume: {name}")
    print(f"Path: {path}")
    print(f"{'='*60}")

    # Use lsof to find processes using this volume
    try:
        result = subprocess.run(
            ['lsof', '+f', '--', path],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.stdout.strip():
            print(result.stdout)
        else:
            print("✅ No processes found using this volume")
    except subprocess.TimeoutExpired:
        print("⚠️  lsof timed out (drive may be busy)")
    except Exception as e:
        print(f"⚠️  Error checking: {e}")

    print()

PYTHON_SCRIPT

echo ""
echo "===================================="
echo "  Common Culprits"
echo "===================================="
echo ""
echo "If you see these processes, they may slow unmounting:"
echo "  - mds, mdworker: Spotlight indexing"
echo "  - backupd: Time Machine"
echo "  - photolibraryd: Photos app"
echo "  - Finder: Open windows"
echo ""
echo "To speed up ejection:"
echo "  1. Disable Spotlight on these drives:"
echo "     sudo mdutil -i off /Volumes/Caoshu1"
echo "     sudo mdutil -i off /Volumes/Caoshu2"
echo "     sudo mdutil -i off /Volumes/Kaishu1"
echo ""
echo "  2. Close Finder windows showing these drives"
echo ""
echo "  3. Check Time Machine isn't backing up to these"
echo ""
echo "  4. Use --force flag (may lose unsaved data):"
echo "     eject-disks eject --force"
echo ""
