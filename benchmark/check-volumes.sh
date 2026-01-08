#!/bin/bash
#
# Check which volumes are ejectable and why some might fail
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="${SCRIPT_DIR}/../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"

echo "===================================="
echo "  Volume Ejection Analysis"
echo "===================================="
echo ""

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "❌ Binary not found. Build first: cd ../swift && ./build.sh"
    exit 1
fi

# Get volumes
VOLUME_JSON=$("$BINARY_PATH" list --compact)
COUNT=$(echo "$VOLUME_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['count'])")

echo "Found $COUNT volume(s) detected by binary"
echo ""

if [[ $COUNT -eq 0 ]]; then
    echo "⚠️  No volumes found."
    echo ""
    echo "Suggestions:"
    echo "  1. Plug in USB flash drives"
    echo "  2. Check external drives are mounted"
    echo "  3. Try: diskutil list external"
    exit 0
fi

echo "Detailed Volume Information:"
echo "============================"
echo ""

# Parse each volume
echo "$VOLUME_JSON" | python3 << 'PYTHON_SCRIPT'
import sys
import json

data = json.load(sys.stdin)

for i, vol in enumerate(data['volumes'], 1):
    name = vol['name']
    path = vol['path']
    bsd = vol.get('bsdName', 'unknown')
    ejectable = vol.get('isEjectable', False)
    removable = vol.get('isRemovable', False)

    print(f"{i}. {name}")
    print(f"   Path: {path}")
    print(f"   BSD:  {bsd}")
    print(f"   Ejectable: {'✅ YES' if ejectable else '❌ NO'}")
    print(f"   Removable: {'✅ YES' if removable else '❌ NO'}")

    # Assess likel reason if not ejectable
    if not ejectable and not removable:
        print(f"   ⚠️  Likely: Network share, APFS volume, or requires admin privileges")
    elif ejectable or removable:
        print(f"   ✅ Should eject successfully")

    print()

PYTHON_SCRIPT

echo ""
echo "===================================="
echo "  Recommendations"
echo "===================================="
echo ""

# Check for real USB drives
REAL_USB=$(diskutil list external physical 2>/dev/null | grep -c "/dev/disk" || echo "0")

if [[ $REAL_USB -gt 0 ]]; then
    echo "✅ Found $REAL_USB external physical disk(s) on system"
    echo ""
    echo "To see them:"
    echo "  diskutil list external physical"
else
    echo "⚠️  No external physical disks found on system"
    echo ""
    echo "The volumes above may be:"
    echo "  - Network shares (AFP, SMB, NFS)"
    echo "  - Disk images (DMG files)"
    echo "  - APFS volumes requiring admin privileges"
fi

echo ""
echo "Next steps:"
echo ""
echo "1. For BEST benchmark results:"
echo "   - Plug in 2-3 USB flash drives"
echo "   - They should show isEjectable: true"
echo "   - Run: ./benchmark-suite.sh --runs 10 --output usb.json"
echo ""
echo "2. To eject current volumes (if they need admin):"
echo "   - Run with sudo: sudo ./debug-eject.sh"
echo "   - Or install privileged helper:"
echo "     cd ../org.deverman.ejectalldisks.sdPlugin/bin"
echo "     sudo ./install-eject-privileges.sh"
echo ""
echo "3. To test Jettison comparison:"
echo "   - Install Jettison from https://www.stclairsoft.com/Jettison/"
echo "   - Run: ./benchmark-suite.sh --runs 10 --output comparison.json"
echo ""
