#!/bin/bash
#
# Quick comparison: Native API vs diskutil with real drives
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Method Comparison Test"
echo "===================================="
echo ""

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "❌ Binary not found. Build first: cd ../swift && ./build.sh"
    exit 1
fi

# Check for volumes
VOLUME_COUNT=$("$BINARY_PATH" count)
if [[ $VOLUME_COUNT -eq 0 ]]; then
    echo "⚠️  No volumes to eject"
    exit 1
fi

echo "Found $VOLUME_COUNT volume(s)"
echo ""
"$BINARY_PATH" list --compact | python3 -m json.tool 2>/dev/null || "$BINARY_PATH" list --compact
echo ""

# Test if sudo needed
TEST_OUTPUT=$("$BINARY_PATH" eject --compact 2>&1)
USE_SUDO=""
if echo "$TEST_OUTPUT" | grep -q "Not privileged"; then
    USE_SUDO="sudo"
    echo "⚠️  Requires sudo for these drives"

    # Remount drives
    echo "Please remount your drives, then press Enter..."
    read -r
    echo ""
fi

# Test 1: Native API
echo "===================================="
echo "TEST 1: Native DiskArbitration API"
echo "===================================="
echo ""

START=$(date +%s.%N)
OUTPUT=$($USE_SUDO "$BINARY_PATH" eject --compact 2>&1)
END=$(date +%s.%N)
NATIVE_TIME=$(echo "$END - $START" | bc)

echo "$OUTPUT" | grep "SwiftDiskArbitration"
echo ""
if echo "$OUTPUT" | grep -q '"successCount"'; then
    SUCCESS=$(echo "$OUTPUT" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
    TOTAL=$(echo "$OUTPUT" | grep -o '"totalCount":[0-9]*' | grep -o '[0-9]*')
    DURATION=$(echo "$OUTPUT" | grep -o '"totalDuration":[0-9.]*' | grep -o '[0-9.]*')
    echo "Result: $SUCCESS/$TOTAL ejected in ${DURATION}s"
fi
echo ""

# Remount for next test
echo "Please remount your drives, then press Enter to test diskutil..."
read -r
echo ""

# Test 2: diskutil
echo "===================================="
echo "TEST 2: diskutil subprocess"
echo "===================================="
echo ""

START=$(date +%s.%N)
OUTPUT=$($USE_SUDO "$BINARY_PATH" eject --use-diskutil --compact 2>&1)
END=$(date +%s.%N)
DISKUTIL_TIME=$(echo "$END - $START" | bc)

if echo "$OUTPUT" | grep -q '"successCount"'; then
    SUCCESS=$(echo "$OUTPUT" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
    TOTAL=$(echo "$OUTPUT" | grep -o '"totalCount":[0-9]*' | grep -o '[0-9]*')
    DURATION=$(echo "$OUTPUT" | grep -o '"totalDuration":[0-9.]*' | grep -o '[0-9.]*')
    echo "Result: $SUCCESS/$TOTAL ejected in ${DURATION}s"
fi
echo ""

# Comparison
echo "===================================="
echo "  Comparison"
echo "===================================="
echo ""
echo "Native API:     ${NATIVE_TIME}s"
echo "diskutil:       ${DISKUTIL_TIME}s"
echo ""

if (( $(echo "$NATIVE_TIME < $DISKUTIL_TIME" | bc -l) )); then
    SPEEDUP=$(echo "scale=2; $DISKUTIL_TIME / $NATIVE_TIME" | bc)
    echo "✅ Native API is ${SPEEDUP}x faster"
else
    echo "⚠️  Both methods show similar times"
    echo "    This suggests macOS unmount time is the bottleneck,"
    echo "    not the ejection method itself."
fi
echo ""
echo "Key insight:"
echo "  - If both are ~11s: macOS is slow to unmount these drives"
echo "  - If native is faster: Your code optimization is working!"
echo ""
