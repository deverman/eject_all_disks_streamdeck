#!/bin/bash
# Debug version of check-blocking to see what's happening

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Debug: Volume List Parsing"
echo "===================================="
echo ""

echo "Step 1: Getting raw output from binary..."
RAW_OUTPUT=$("$BINARY_PATH" list --compact 2>&1)
echo "Raw output length: ${#RAW_OUTPUT} characters"
echo "---"
echo "$RAW_OUTPUT"
echo "---"
echo ""

echo "Step 2: Filtering out debug lines..."
VOLUMES=$(echo "$RAW_OUTPUT" | grep -v "SwiftDiskArbitration" | grep -v "DiskSession")
echo "Filtered output length: ${#VOLUMES} characters"
echo "---"
echo "$VOLUMES"
echo "---"
echo ""

echo "Step 3: Testing JSON parse..."
if echo "$VOLUMES" | python3 -c "import sys, json; data = json.load(sys.stdin); print('✅ SUCCESS: Found', data['count'], 'volumes')" 2>&1; then
    echo ""
    echo "JSON parsing works!"
else
    echo ""
    echo "❌ JSON parsing failed"
    echo ""
    echo "This means the filtered output is not valid JSON."
    echo "Check if there are other debug lines that need filtering."
fi
echo ""

echo "Step 4: Testing piping to Python script..."
RESULT=$(echo "$VOLUMES" | python3 << 'PYTHON_SCRIPT'
import sys
import json

try:
    data = json.load(sys.stdin)
    print(f"SUCCESS: Got {data['count']} volumes")
    for vol in data['volumes']:
        print(f"  - {vol['name']}")
except Exception as e:
    print(f"ERROR: {e}")
PYTHON_SCRIPT
)
echo "$RESULT"
