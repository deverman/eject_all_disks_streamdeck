#!/bin/bash
#
# Test script for the Swift-native Stream Deck plugin
#
# Runs the Swift Testing test suite
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Running EjectAllDisksPlugin Tests...${NC}"
echo ""

# Change to the swift-plugin directory
cd "$SCRIPT_DIR"

# Run tests
if [ "$1" == "--verbose" ]; then
    echo -e "${YELLOW}Running tests with verbose output...${NC}"
    swift test --verbose
elif [ "$1" == "--filter" ] && [ -n "$2" ]; then
    echo -e "${YELLOW}Running filtered tests: $2${NC}"
    swift test --filter "$2"
else
    swift test
fi

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
