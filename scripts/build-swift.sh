#!/bin/bash
#
# Build Swift disk ejection tool using Swift Package Manager
#
# Builds for the native architecture (arm64 on Apple Silicon).
# Since macOS 15+ is required, all target Macs support arm64.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SWIFT_PKG="$PROJECT_ROOT/swift"
OUTPUT_DIR="$PROJECT_ROOT/org.deverman.ejectalldisks.sdPlugin/bin"
OUTPUT_BIN="$OUTPUT_DIR/eject-disks"

echo "Building Swift disk ejection tool..."

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if Swift is available
if ! command -v swift &> /dev/null; then
    echo "Error: Swift not found"
    echo "Please install Swift from https://www.swift.org/install/"
    exit 1
fi

# Show Swift version
echo "Swift version: $(swift --version | head -1)"

# Check if Package.swift exists
if [ ! -f "$SWIFT_PKG/Package.swift" ]; then
    echo "Error: Package.swift not found at $SWIFT_PKG"
    exit 1
fi

cd "$SWIFT_PKG"

# Build for release (native architecture)
echo "Building release configuration..."
swift build -c release

# Find and copy the built binary
BUILD_BIN="$SWIFT_PKG/.build/release/eject-disks"

if [ -f "$BUILD_BIN" ]; then
    cp "$BUILD_BIN" "$OUTPUT_BIN"
    chmod +x "$OUTPUT_BIN"

    echo ""
    echo "Build complete!"
    echo "Output: $OUTPUT_BIN"

    # Show binary info
    echo ""
    echo "Binary info:"
    file "$OUTPUT_BIN"
    ls -lh "$OUTPUT_BIN"

    # Show help output
    echo ""
    echo "Command help:"
    "$OUTPUT_BIN" --help
else
    echo "Error: Build succeeded but binary not found at $BUILD_BIN"
    exit 1
fi
