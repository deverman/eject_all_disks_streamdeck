#!/bin/bash
#
# Build the Swift binary and copy it to the plugin directory
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Swift binary..."
swift build -c release

echo "Copying binary to plugin directory..."
cp .build/release/eject-disks ../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks

echo "✅ Build complete!"
echo "Binary location: ../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks"
echo ""
echo "Test it:"
echo "  ../org.deverman.ejectalldisks.sdPlugin/bin/eject-disks list"
echo ""
echo "Run benchmarks:"
echo "  cd ../benchmark"
echo "  ./benchmark-suite.sh --create-dmgs 3 --runs 5 --output quick.json"
