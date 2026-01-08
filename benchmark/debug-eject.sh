#!/bin/bash
#
# Debug script to test ejection performance with detailed timing
# Automatically handles admin privileges for external drives
#

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
echo "Found $VOLUME_COUNT volume(s)"
echo ""

if [[ $VOLUME_COUNT -eq 0 ]]; then
    echo "⚠️  No volumes found to eject."
    exit 1
fi

# Show volumes
echo "Volumes:"
"$BINARY_PATH" list --compact | python3 -m json.tool 2>/dev/null || "$BINARY_PATH" list --compact
echo ""

# Function to test ejection
run_eject_test() {
    local use_sudo=$1
    local cmd_prefix=""

    if [[ "$use_sudo" == "true" ]]; then
        cmd_prefix="sudo"
        echo "Running with administrator privileges..."
    else
        echo "Attempting ejection..."
    fi
    echo ""
    echo "---"

    # Time the operation
    START=$(date +%s.%N)
    OUTPUT=$($cmd_prefix "$BINARY_PATH" eject --compact 2>&1)
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
        echo "  Duration: ${JSON_DURATION}s"
        echo ""

        # Check if all failed with permission error
        if [[ $SUCCESS -eq 0 ]] && [[ $FAILED -gt 0 ]] && echo "$OUTPUT" | grep -q "Not privileged"; then
            return 1  # Permission error
        elif [[ $SUCCESS -gt 0 ]]; then
            # Show performance assessment
            if (( $(echo "$JSON_DURATION < 1.0" | bc -l) )); then
                echo "✅ PERFORMANCE: Fast! (${JSON_DURATION}s)"
            elif (( $(echo "$JSON_DURATION < 5" | bc -l) )); then
                echo "✅ PERFORMANCE: Good (${JSON_DURATION}s)"
            else
                echo "⚠️  PERFORMANCE: Slow (${JSON_DURATION}s)"
            fi
            return 0  # Success
        else
            return 2  # Other error
        fi
    fi

    return 2  # Unknown error
}

# Test 1: Try without sudo first
echo "===================================="
echo "TEST: Native DiskArbitration API"
echo "===================================="
echo ""

run_eject_test "false"
result=$?

# If permission error, automatically retry with sudo
if [[ $result -eq 1 ]]; then
    echo ""
    echo "⚠️  Administrator privileges required for these drives"
    echo ""
    echo "Thunderbolt/external drives often require admin privileges."
    echo "Re-running with sudo..."
    echo ""
    echo "===================================="
    echo "RETRY: With Administrator Privileges"
    echo "===================================="
    echo ""

    run_eject_test "true"
    result=$?
fi

echo ""
echo "===================================="
echo "  Done"
echo "===================================="
echo ""

if [[ $result -eq 0 ]]; then
    echo "✅ Ejection successful!"
    echo ""
    echo "Check the [SwiftDiskArbitration] debug output above for timing:"
    echo "  - unmountCallback: shows how long macOS took to unmount"
    echo "  - ejectCallback: shows how long physical eject took"
    echo ""
    echo "Next: Run full benchmark with:"
    echo "  ./benchmark-suite.sh --runs 10 --output results.json"
else
    echo "❌ Ejection failed"
    echo ""
    echo "Check the error messages above for details."
fi
echo ""
