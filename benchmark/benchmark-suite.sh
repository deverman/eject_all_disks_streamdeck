#!/bin/bash
#
# Comprehensive Disk Ejection Benchmark Suite
# Compares: Native API vs diskutil vs Jettison
#
# Usage: ./benchmark-suite.sh [options]
#   --runs N          Number of test runs per method (default: 5)
#   --skip-jettison   Skip Jettison benchmarks
#   --output FILE     Save results to JSON file
#   --create-dmgs N   Create N test disk images for consistent testing
#

set -e

# Configuration
RUNS=5
SKIP_JETTISON=false
OUTPUT_FILE=""
CREATE_DMGS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --skip-jettison)
            SKIP_JETTISON=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --create-dmgs)
            CREATE_DMGS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if eject-disks binary exists
if [[ ! -f "$BINARY_PATH" ]]; then
    echo -e "${RED}Error: eject-disks binary not found at $BINARY_PATH${NC}"
    echo "Please build the Swift binary first with: cd swift && swift build -c release"
    exit 1
fi

# Check if Jettison is installed
JETTISON_PATH="/Applications/Jettison.app/Contents/MacOS/Jettison"
if [[ -f "$JETTISON_PATH" && "$SKIP_JETTISON" == false ]]; then
    HAS_JETTISON=true
else
    HAS_JETTISON=false
    if [[ "$SKIP_JETTISON" == false ]]; then
        echo -e "${YELLOW}Warning: Jettison not found at $JETTISON_PATH${NC}"
        echo "Install Jettison to include it in benchmarks, or use --skip-jettison"
    fi
fi

echo "=================================="
echo "  Disk Ejection Benchmark Suite"
echo "=================================="
echo ""
echo "Configuration:"
echo "  Runs per method: $RUNS"
echo "  Jettison available: $HAS_JETTISON"
echo "  Binary: $BINARY_PATH"
echo ""

# Create test disk images if requested
DMG_PATHS=()
if [[ $CREATE_DMGS -gt 0 ]]; then
    echo -e "${BLUE}Creating $CREATE_DMGS test disk images...${NC}"
    TEMP_DIR=$(mktemp -d)

    for i in $(seq 1 $CREATE_DMGS); do
        DMG_PATH="$TEMP_DIR/TestDisk${i}.dmg"
        hdiutil create -size 10m -fs HFS+ -volname "TestDisk${i}" "$DMG_PATH" >/dev/null 2>&1
        hdiutil attach "$DMG_PATH" >/dev/null 2>&1
        DMG_PATHS+=("$DMG_PATH")
        echo "  Created and mounted: TestDisk${i}"
    done
    echo ""

    # Trap to cleanup DMGs on exit
    trap 'echo "Cleaning up test disk images..."; for dmg in "${DMG_PATHS[@]}"; do hdiutil detach "/Volumes/$(basename "$dmg" .dmg)" >/dev/null 2>&1 || true; rm -f "$dmg"; done; rm -rf "$TEMP_DIR"' EXIT
fi

# Get list of ejectable volumes
echo -e "${BLUE}Detecting ejectable volumes...${NC}"
VOLUME_COUNT=$("$BINARY_PATH" count)
echo "  Found $VOLUME_COUNT ejectable volume(s)"

if [[ $VOLUME_COUNT -eq 0 ]]; then
    echo -e "${RED}Error: No ejectable volumes found. Please mount some external disks or use --create-dmgs${NC}"
    exit 1
fi

"$BINARY_PATH" list --compact
echo ""

# Function to remount all volumes
remount_volumes() {
    if [[ ${#DMG_PATHS[@]} -gt 0 ]]; then
        # Remount test DMGs
        for dmg in "${DMG_PATHS[@]}"; do
            hdiutil attach "$dmg" >/dev/null 2>&1 || true
        done
    else
        # For real volumes, we can't auto-remount - user must do it manually
        echo -e "${YELLOW}Please remount all volumes manually, then press Enter to continue...${NC}"
        read -r
    fi

    # Wait for volumes to stabilize
    sleep 2
}

# Function to benchmark a method
benchmark_method() {
    local method_name="$1"
    local method_cmd="$2"
    local results_file="$3"

    echo -e "${GREEN}Benchmarking: $method_name${NC}"
    echo "  Running $RUNS tests..."

    local times=()
    local success_counts=()
    local total_counts=()

    for run in $(seq 1 $RUNS); do
        echo -n "  Run $run/$RUNS: "

        # Run the ejection command and capture output
        local start_time=$(date +%s.%N)
        local output
        output=$(eval "$method_cmd" 2>&1)
        local end_time=$(date +%s.%N)

        local elapsed=$(echo "$end_time - $start_time" | bc)
        times+=("$elapsed")

        # Parse output for success/failure counts if available
        if echo "$output" | grep -q "successCount"; then
            local success=$(echo "$output" | grep -o '"successCount":[0-9]*' | grep -o '[0-9]*')
            local total=$(echo "$output" | grep -o '"totalCount":[0-9]*' | grep -o '[0-9]*')
            success_counts+=("$success")
            total_counts+=("$total")
            echo "${elapsed}s (${success}/${total} ejected)"
        else
            echo "${elapsed}s"
        fi

        # Save raw output
        echo "$output" >> "$results_file"
        echo "---" >> "$results_file"

        # Remount for next run (except on last run)
        if [[ $run -lt $RUNS ]]; then
            remount_volumes
        fi
    done

    # Calculate statistics
    local sum=0
    local min=${times[0]}
    local max=${times[0]}

    for time in "${times[@]}"; do
        sum=$(echo "$sum + $time" | bc)
        if (( $(echo "$time < $min" | bc -l) )); then
            min=$time
        fi
        if (( $(echo "$time > $max" | bc -l) )); then
            max=$time
        fi
    done

    local avg=$(echo "scale=4; $sum / ${#times[@]}" | bc)

    # Calculate standard deviation
    local variance=0
    for time in "${times[@]}"; do
        local diff=$(echo "$time - $avg" | bc)
        local sq=$(echo "$diff * $diff" | bc)
        variance=$(echo "$variance + $sq" | bc)
    done
    variance=$(echo "scale=4; $variance / ${#times[@]}" | bc)
    local stddev=$(echo "scale=4; sqrt($variance)" | bc)

    echo ""
    echo "  Results:"
    echo "    Average: ${avg}s"
    echo "    Min:     ${min}s"
    echo "    Max:     ${max}s"
    echo "    StdDev:  ${stddev}s"
    echo ""

    # Return average time (we'll capture it via echo)
    echo "$avg"
}

# Create results directory
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "$RESULTS_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_BASE="${RESULTS_DIR}/benchmark_${TIMESTAMP}"

# Benchmark 1: Native API
echo "========================================="
echo "TEST 1: Native DiskArbitration API"
echo "========================================="
NATIVE_AVG=$(benchmark_method \
    "Native API (DADiskUnmount)" \
    "\"$BINARY_PATH\" eject --compact" \
    "${RESULTS_BASE}_native.txt")

echo "Remounting volumes for next test..."
remount_volumes
echo ""

# Benchmark 2: diskutil
echo "========================================="
echo "TEST 2: diskutil subprocess"
echo "========================================="
DISKUTIL_AVG=$(benchmark_method \
    "diskutil subprocess" \
    "\"$BINARY_PATH\" eject --use-diskutil --compact" \
    "${RESULTS_BASE}_diskutil.txt")

# Benchmark 3: Jettison (if available)
if [[ "$HAS_JETTISON" == true ]]; then
    echo "Remounting volumes for Jettison test..."
    remount_volumes
    echo ""

    echo "========================================="
    echo "TEST 3: Jettison"
    echo "========================================="

    # Note: Jettison doesn't have a command-line interface
    # We'll need to measure it differently - via AppleScript
    JETTISON_AVG=$(benchmark_method \
        "Jettison (via AppleScript)" \
        "osascript -e 'tell application \"Jettison\" to eject all disks'" \
        "${RESULTS_BASE}_jettison.txt")
fi

# Generate comparison report
echo ""
echo "========================================="
echo "           FINAL RESULTS"
echo "========================================="
echo ""

printf "%-25s %10s %10s\n" "Method" "Avg Time" "Speedup"
printf "%-25s %10s %10s\n" "-------------------------" "----------" "----------"

# Native
printf "%-25s %10.4fs %10s\n" "Native API" "$NATIVE_AVG" "1.00x"

# diskutil
DISKUTIL_SPEEDUP=$(echo "scale=2; $DISKUTIL_AVG / $NATIVE_AVG" | bc)
printf "%-25s %10.4fs %10.2fx\n" "diskutil subprocess" "$DISKUTIL_AVG" "$DISKUTIL_SPEEDUP"

# Jettison
if [[ "$HAS_JETTISON" == true ]]; then
    JETTISON_SPEEDUP=$(echo "scale=2; $JETTISON_AVG / $NATIVE_AVG" | bc)
    printf "%-25s %10.4fs %10.2fx\n" "Jettison" "$JETTISON_AVG" "$JETTISON_SPEEDUP"
fi

echo ""
echo "Summary:"
echo "  Native API is ${DISKUTIL_SPEEDUP}x faster than diskutil"
if [[ "$HAS_JETTISON" == true ]]; then
    echo "  Native API is ${JETTISON_SPEEDUP}x faster than Jettison"
fi

# Generate JSON output
if [[ -n "$OUTPUT_FILE" ]]; then
    cat > "$OUTPUT_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "volumeCount": $VOLUME_COUNT,
  "runsPerMethod": $RUNS,
  "results": {
    "native": {
      "avgTime": $NATIVE_AVG,
      "speedup": 1.0
    },
    "diskutil": {
      "avgTime": $DISKUTIL_AVG,
      "speedup": $DISKUTIL_SPEEDUP
    }$(if [[ "$HAS_JETTISON" == true ]]; then echo ",
    \"jettison\": {
      \"avgTime\": $JETTISON_AVG,
      \"speedup\": $JETTISON_SPEEDUP
    }"; fi)
  }
}
EOF
    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

echo ""
echo "Detailed logs saved to: ${RESULTS_BASE}_*.txt"
