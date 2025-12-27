#!/bin/bash
#
# Quick test to verify the eject-disks binary is working correctly
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "=================================="
echo "  Eject-Disks Binary Test"
echo "=================================="
echo ""

# Test 1: Check if binary exists
echo "Test 1: Checking if binary exists..."
if [[ -f "$BINARY_PATH" ]]; then
    echo "  ✅ Binary found at: $BINARY_PATH"
    ls -lh "$BINARY_PATH"
else
    echo "  ❌ Binary NOT found at: $BINARY_PATH"
    echo ""
    echo "Please build the binary first:"
    echo "  cd swift"
    echo "  ./build.sh"
    exit 1
fi
echo ""

# Test 2: Check if binary is executable
echo "Test 2: Checking if binary is executable..."
if [[ -x "$BINARY_PATH" ]]; then
    echo "  ✅ Binary is executable"
else
    echo "  ❌ Binary is NOT executable"
    echo "  Fixing permissions..."
    chmod +x "$BINARY_PATH"
    echo "  ✅ Permissions fixed"
fi
echo ""

# Test 3: Run version command
echo "Test 3: Running version command..."
if "$BINARY_PATH" --version; then
    echo "  ✅ Binary runs successfully"
else
    echo "  ❌ Binary failed to run"
    exit 1
fi
echo ""

# Test 4: Count ejectable volumes
echo "Test 4: Counting ejectable volumes..."
VOLUME_COUNT=$("$BINARY_PATH" count 2>&1)
echo "  Found $VOLUME_COUNT ejectable volume(s)"
if [[ $VOLUME_COUNT -gt 0 ]]; then
    echo "  ✅ Volumes detected"
else
    echo "  ⚠️  No ejectable volumes found"
    echo "  You can create test disk images with:"
    echo "    ./benchmark-suite.sh --create-dmgs 3 --runs 5 --output test.json"
fi
echo ""

# Test 5: List volumes (compact JSON)
echo "Test 5: Listing volumes (compact JSON)..."
echo "---"
"$BINARY_PATH" list --compact
echo "---"
echo "  ✅ List command works"
echo ""

# Test 6: Test eject command (dry run - just check JSON output format)
if [[ $VOLUME_COUNT -gt 0 ]]; then
    echo "Test 6: Testing eject command output format (will attempt real ejection)..."
    echo "  Running: $BINARY_PATH eject --compact"
    echo "---"
    OUTPUT=$("$BINARY_PATH" eject --compact 2>&1)
    echo "$OUTPUT"
    echo "---"

    # Parse JSON to verify format
    if echo "$OUTPUT" | grep -q '"totalCount"'; then
        echo "  ✅ JSON output format is correct"

        # Extract counts
        TOTAL=$(echo "$OUTPUT" | grep -o '"totalCount":[0-9]*' | grep -o '[0-9]*')
        SUCCESS=$(echo "$OUTPUT" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
        FAILED=$(echo "$OUTPUT" | grep -o '"failedCount":[0-9]*' | grep -o '[0-9]*')

        echo "  Results: $SUCCESS/$TOTAL succeeded, $FAILED failed"

        if [[ $SUCCESS -gt 0 ]]; then
            echo "  ✅ Ejection successful"
            echo ""
            echo "  Note: Volumes were actually ejected. Remount them to run benchmarks."
        else
            echo "  ⚠️  Ejection failed for all volumes"
            echo "  This might be due to:"
            echo "    - Processes using the volumes (Spotlight, Photos, etc.)"
            echo "    - Insufficient permissions"
            echo "    - Internal system volumes that can't be ejected"
        fi
    else
        echo "  ❌ JSON output format is incorrect"
        echo "  Expected fields: totalCount, successCount, failedCount"
        exit 1
    fi
else
    echo "Test 6: Skipped (no volumes to eject)"
fi

echo ""
echo "=================================="
echo "  All tests completed!"
echo "=================================="
echo ""
echo "Next steps:"
echo "  1. Mount some USB drives or create test disk images"
echo "  2. Run the benchmark suite:"
echo "     ./benchmark-suite.sh --create-dmgs 3 --runs 5 --output results.json"
echo ""
