#!/bin/bash
#
# Build Swift disk ejection tool
#
# This script compiles the Swift source into a universal binary
# that runs on both Intel and Apple Silicon Macs.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SWIFT_SRC="$PROJECT_ROOT/swift/EjectDisks.swift"
OUTPUT_DIR="$PROJECT_ROOT/org.deverman.ejectalldisks.sdPlugin/bin"
OUTPUT_BIN="$OUTPUT_DIR/eject-disks"

echo "Building Swift disk ejection tool..."

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if Swift is available
if ! command -v swiftc &> /dev/null; then
    echo "Error: Swift compiler (swiftc) not found"
    echo "Please install Xcode or Xcode Command Line Tools"
    exit 1
fi

# Check if source exists
if [ ! -f "$SWIFT_SRC" ]; then
    echo "Error: Swift source not found at $SWIFT_SRC"
    exit 1
fi

# Compile for both architectures (universal binary)
# -O for optimizations
# -whole-module-optimization for better performance
# -target for architecture-specific builds

echo "Compiling for arm64..."
swiftc -O -whole-module-optimization \
    -target arm64-apple-macosx11.0 \
    -o "${OUTPUT_BIN}-arm64" \
    "$SWIFT_SRC" 2>/dev/null || {
    echo "arm64 build failed, trying without target..."
    swiftc -O -whole-module-optimization \
        -o "${OUTPUT_BIN}-arm64" \
        "$SWIFT_SRC"
}

echo "Compiling for x86_64..."
swiftc -O -whole-module-optimization \
    -target x86_64-apple-macosx10.15 \
    -o "${OUTPUT_BIN}-x86_64" \
    "$SWIFT_SRC" 2>/dev/null || {
    echo "x86_64 build skipped (not supported on this machine)"
    # Just use the arm64 build
    cp "${OUTPUT_BIN}-arm64" "$OUTPUT_BIN"
    rm -f "${OUTPUT_BIN}-arm64"
    echo "Built single-architecture binary"
    echo "Output: $OUTPUT_BIN"
    exit 0
}

echo "Creating universal binary..."
lipo -create \
    "${OUTPUT_BIN}-arm64" \
    "${OUTPUT_BIN}-x86_64" \
    -output "$OUTPUT_BIN"

# Cleanup intermediate files
rm -f "${OUTPUT_BIN}-arm64" "${OUTPUT_BIN}-x86_64"

# Make executable
chmod +x "$OUTPUT_BIN"

echo "Build complete!"
echo "Output: $OUTPUT_BIN"

# Show binary info
echo ""
echo "Binary info:"
file "$OUTPUT_BIN"
ls -lh "$OUTPUT_BIN"
