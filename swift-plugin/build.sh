#!/bin/bash
#
# Build script for the Swift-native Stream Deck plugin
#
# Usage:
#   ./build.sh          - Build only (for development)
#   ./build.sh --install - Build and install to Stream Deck
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

echo -e "${GREEN}Build succeeded!${NC}"

# Install to Stream Deck if requested
if [ "$1" == "--install" ]; then
    echo ""
    echo -e "${YELLOW}Installing to Stream Deck...${NC}"

    INSTALL_DIR="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins/org.deverman.ejectalldisks.sdPlugin"

    # Export plugin with generated manifest (this builds debug, but we'll overwrite)
    swift run org.deverman.ejectalldisks export org.deverman.ejectalldisks \
        --generate-manifest \
        --copy-executable

    # IMPORTANT: Copy the RELEASE binary over the debug binary that export created
    # The export command builds debug, but we want the optimized release build
    echo -e "${YELLOW}Copying release binary...${NC}"
    cp ".build/release/org.deverman.ejectalldisks" "$INSTALL_DIR/org.deverman.ejectalldisks"

    # Copy assets (images, UI, and libs)
    cp -r "$PLUGIN_DIR/imgs" "$INSTALL_DIR/"
    cp -r "$PLUGIN_DIR/ui" "$INSTALL_DIR/"
    cp -r "$PLUGIN_DIR/libs" "$INSTALL_DIR/" 2>/dev/null || true

    echo -e "${GREEN}Plugin installed!${NC}"
    echo ""
    echo "To activate, restart the plugin:"
    echo "  streamdeck restart org.deverman.ejectalldisks"
else
    echo ""
    echo -e "${GREEN}Build complete!${NC}"
    echo ""
    echo "To install the plugin to Stream Deck:"
    echo "  ./build.sh --install"
fi
