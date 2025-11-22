#!/bin/bash
#
# Build Swift disk ejection tool using Swift Package Manager
#
# This script compiles the Swift package into a universal binary
# that runs on both Intel and Apple Silicon Macs.
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
    echo "Please install Xcode or Xcode Command Line Tools"
    exit 1
fi

# Check if Package.swift exists
if [ ! -f "$SWIFT_PKG/Package.swift" ]; then
    echo "Error: Package.swift not found at $SWIFT_PKG"
    exit 1
fi

cd "$SWIFT_PKG"

# Build for release
echo "Building release configuration..."

# Try to build universal binary (both architectures)
echo "Attempting universal binary build (arm64 + x86_64)..."

# Build for arm64
echo "Building for arm64..."
swift build -c release --arch arm64 2>/dev/null && ARM64_SUCCESS=true || ARM64_SUCCESS=false

# Build for x86_64
echo "Building for x86_64..."
swift build -c release --arch x86_64 2>/dev/null && X86_SUCCESS=true || X86_SUCCESS=false

if [ "$ARM64_SUCCESS" = true ] && [ "$X86_SUCCESS" = true ]; then
    echo "Creating universal binary..."

    # Find the built binaries
    ARM64_BIN="$SWIFT_PKG/.build/arm64-apple-macosx/release/eject-disks"
    X86_BIN="$SWIFT_PKG/.build/x86_64-apple-macosx/release/eject-disks"

    if [ -f "$ARM64_BIN" ] && [ -f "$X86_BIN" ]; then
        lipo -create "$ARM64_BIN" "$X86_BIN" -output "$OUTPUT_BIN"
        echo "Universal binary created successfully"
    else
        echo "Warning: Could not find architecture-specific binaries"
        echo "Falling back to default build..."
        swift build -c release
        cp "$SWIFT_PKG/.build/release/eject-disks" "$OUTPUT_BIN"
    fi
elif [ "$ARM64_SUCCESS" = true ]; then
    echo "x86_64 build failed, using arm64 only..."
    cp "$SWIFT_PKG/.build/arm64-apple-macosx/release/eject-disks" "$OUTPUT_BIN"
elif [ "$X86_SUCCESS" = true ]; then
    echo "arm64 build failed, using x86_64 only..."
    cp "$SWIFT_PKG/.build/x86_64-apple-macosx/release/eject-disks" "$OUTPUT_BIN"
else
    echo "Architecture-specific builds failed, trying default build..."
    swift build -c release
    cp "$SWIFT_PKG/.build/release/eject-disks" "$OUTPUT_BIN"
fi

# Make executable
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
