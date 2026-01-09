#!/bin/bash
#
# Build script for the Swift-native Stream Deck plugin
#
# This script builds the EjectAllDisksPlugin and copies the binary
# to the plugin bundle directory.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$PROJECT_ROOT/org.deverman.ejectalldisks.sdPlugin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building EjectAllDisksPlugin...${NC}"

# Change to the swift-plugin directory
cd "$SCRIPT_DIR"

# Build for release
echo -e "${YELLOW}Running swift build...${NC}"
swift build -c release

# Check if build succeeded
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build succeeded!${NC}"

# Find the binary
BINARY_PATH="$SCRIPT_DIR/.build/release/org.deverman.ejectalldisks"

if [ ! -f "$BINARY_PATH" ]; then
    echo -e "${RED}Binary not found at: $BINARY_PATH${NC}"
    exit 1
fi

# Create bin directory if it doesn't exist
mkdir -p "$PLUGIN_DIR/bin"

# Copy the binary to the plugin bundle
echo -e "${YELLOW}Copying binary to plugin bundle...${NC}"
cp "$BINARY_PATH" "$PLUGIN_DIR/bin/"

# Make sure it's executable
chmod +x "$PLUGIN_DIR/bin/org.deverman.ejectalldisks"

echo -e "${GREEN}Binary copied to: $PLUGIN_DIR/bin/org.deverman.ejectalldisks${NC}"

# Optionally update manifest to use Swift binary
if [ "$1" == "--update-manifest" ]; then
    echo -e "${YELLOW}Updating manifest.json to use Swift binary...${NC}"
    cp "$PLUGIN_DIR/manifest-swift.json" "$PLUGIN_DIR/manifest.json"
    echo -e "${GREEN}Manifest updated!${NC}"
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "To test the plugin:"
echo "  1. Close Stream Deck application"
echo "  2. Run: ./build.sh --update-manifest"
echo "  3. Open Stream Deck application"
echo "  4. Add the 'Eject All Disks' action to a button"
echo ""
