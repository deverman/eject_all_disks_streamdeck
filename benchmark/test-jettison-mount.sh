#!/bin/bash
#
# Test Jettison's mount functionality via AppleScript
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Jettison Mount Test"
echo "===================================="
echo ""

# Check Jettison is available
if ! command -v osascript &> /dev/null; then
    echo "❌ osascript not available (running on Linux)"
    exit 1
fi

if ! pgrep -x "Jettison" > /dev/null; then
    echo "❌ Jettison is not running"
    echo "Please start Jettison and run this script again"
    exit 1
fi

echo "✅ Jettison is running"
echo ""

# Check current volume count
INITIAL_COUNT=$("$BINARY_PATH" count)
echo "Current mounted volumes: $INITIAL_COUNT"
echo ""

if [[ $INITIAL_COUNT -eq 0 ]]; then
    echo "No volumes are currently mounted."
    echo "Perfect! We can test the mount command."
    echo ""

    echo "Attempting to mount all disks via Jettison..."
    echo "Testing: osascript -e 'tell application \"Jettison\" to mount'"
    echo ""
    echo "Press Enter to continue..."
    read -r

    START=$(date +%s.%N)
    OUTPUT=$(osascript -e 'tell application "Jettison" to mount' 2>&1)
    EXIT_CODE=$?
    END=$(date +%s.%N)
    DURATION=$(echo "$END - $START" | bc)

    echo ""
    if [[ $EXIT_CODE -ne 0 ]]; then
        echo "❌ AppleScript error:"
        echo "$OUTPUT"
        echo ""
        echo "Trying alternative syntax: 'mount all disks'"

        START=$(date +%s.%N)
        OUTPUT=$(osascript -e 'tell application "Jettison" to mount all disks' 2>&1)
        EXIT_CODE=$?
        END=$(date +%s.%N)
        DURATION=$(echo "$END - $START" | bc)

        if [[ $EXIT_CODE -ne 0 ]]; then
            echo "❌ Also failed:"
            echo "$OUTPUT"
        else
            echo "✅ Success with 'mount all disks'"
            MOUNT_CMD="mount all disks"
        fi
    else
        echo "✅ AppleScript succeeded"
        MOUNT_CMD="mount"
    fi

    echo ""
    echo "Command completed in: ${DURATION}s"
    echo ""

    # Check if volumes were mounted
    sleep 2  # Give OS time to recognize mounts
    FINAL_COUNT=$("$BINARY_PATH" count)

    echo "Verification:"
    echo "  Before: $INITIAL_COUNT volumes"
    echo "  After:  $FINAL_COUNT volumes"
    echo ""

    if [[ $FINAL_COUNT -gt $INITIAL_COUNT ]]; then
        MOUNTED=$((FINAL_COUNT - INITIAL_COUNT))
        echo "✅ Success! Mounted $MOUNTED volume(s)"
        echo ""
        echo "For benchmark-suite.sh, use this in remount_volumes():"
        echo "  osascript -e 'tell application \"Jettison\" to $MOUNT_CMD'"
    else
        echo "⚠️  No volumes were mounted"
        echo "You may need to check Jettison's preferences or manually remount"
    fi
else
    echo "Volumes are currently mounted."
    echo "To test the mount command, you need to eject them first."
    echo ""
    echo "Would you like to:"
    echo "  1. Eject all drives and test mount (recommended)"
    echo "  2. Skip this test"
    echo ""
    echo -n "Choice (1 or 2): "
    read -r choice

    if [[ "$choice" == "1" ]]; then
        echo ""
        echo "Ejecting all drives via Jettison..."
        osascript -e 'tell application "Jettison" to eject' 2>&1

        echo "Waiting for ejection to complete..."
        sleep 2

        EJECTED_COUNT=$("$BINARY_PATH" count)
        echo "Volumes remaining: $EJECTED_COUNT"

        if [[ $EJECTED_COUNT -eq 0 ]]; then
            echo ""
            echo "✅ All drives ejected. Now testing mount..."
            echo ""

            START=$(date +%s.%N)
            OUTPUT=$(osascript -e 'tell application "Jettison" to mount' 2>&1)
            EXIT_CODE=$?
            END=$(date +%s.%N)
            DURATION=$(echo "$END - $START" | bc)

            echo ""
            if [[ $EXIT_CODE -ne 0 ]]; then
                echo "❌ AppleScript error with 'mount':"
                echo "$OUTPUT"
                echo ""
                echo "Trying alternative: 'mount all disks'"

                START=$(date +%s.%N)
                OUTPUT=$(osascript -e 'tell application "Jettison" to mount all disks' 2>&1)
                EXIT_CODE=$?
                END=$(date +%s.%N)
                DURATION=$(echo "$END - $START" | bc)

                if [[ $EXIT_CODE -ne 0 ]]; then
                    echo "❌ Also failed:"
                    echo "$OUTPUT"
                else
                    echo "✅ Success with 'mount all disks'"
                    MOUNT_CMD="mount all disks"
                fi
            else
                echo "✅ AppleScript succeeded with 'mount'"
                MOUNT_CMD="mount"
            fi

            echo ""
            echo "Command completed in: ${DURATION}s"
            echo ""

            sleep 2
            FINAL_COUNT=$("$BINARY_PATH" count)

            echo "Verification:"
            echo "  Before: 0 volumes"
            echo "  After:  $FINAL_COUNT volumes"
            echo ""

            if [[ $FINAL_COUNT -gt 0 ]]; then
                echo "✅ Success! Mounted $FINAL_COUNT volume(s)"
                echo ""
                echo "For benchmark-suite.sh, use this in remount_volumes():"
                echo "  osascript -e 'tell application \"Jettison\" to $MOUNT_CMD'"
                echo "  sleep 2  # Wait for volumes to appear"
            else
                echo "⚠️  No volumes were mounted"
            fi
        else
            echo "⚠️  Some volumes still mounted ($EJECTED_COUNT remaining)"
            echo "Cannot test mount command"
        fi
    else
        echo "Test skipped."
    fi
fi

echo ""
echo "===================================="
echo "  Summary"
echo "===================================="
echo ""
echo "If mount works via AppleScript, we can replace the current"
echo "remount_volumes() function that uses 'diskutil mount' with"
echo "a single Jettison AppleScript command, which should be faster."
echo ""
