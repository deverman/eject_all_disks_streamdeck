#!/bin/bash
#
# install-eject-privileges.sh
#
# One-time setup script to allow the eject-disks tool to run without password prompts.
# This configures sudoers to allow passwordless execution of this specific tool.
#
# Usage: bash install-eject-privileges.sh
#
# This script must be run with admin privileges (you'll be prompted for your password).
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EJECT_BINARY="$SCRIPT_DIR/eject-disks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "=========================================="
echo "  Eject All Disks - Privilege Setup"
echo "=========================================="
echo ""

# Check if eject-disks binary exists
if [ ! -f "$EJECT_BINARY" ]; then
    echo -e "${RED}Error: eject-disks binary not found at:${NC}"
    echo "  $EJECT_BINARY"
    echo ""
    echo "Make sure the Stream Deck plugin is properly installed."
    exit 1
fi

# Make sure the binary is executable
chmod +x "$EJECT_BINARY"

# Get the current user
CURRENT_USER=$(whoami)

echo "This script will configure your system to allow the"
echo "eject-disks tool to run without requiring a password each time."
echo ""
echo "Binary path: $EJECT_BINARY"
echo "User: $CURRENT_USER"
echo ""
echo -e "${YELLOW}You will be prompted for your admin password.${NC}"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Create the sudoers rule
SUDOERS_FILE="/etc/sudoers.d/eject-disks"
SUDOERS_RULE="$CURRENT_USER ALL=(ALL) NOPASSWD: $EJECT_BINARY *"

echo ""
echo "Creating sudoers rule..."

# Use sudo to create the sudoers file
# The file must have mode 0440 and be owned by root
sudo bash -c "cat > '$SUDOERS_FILE'" << EOF
# Allow $CURRENT_USER to run eject-disks without password
# Created by install-eject-privileges.sh
# Safe to delete if you uninstall the Eject All Disks plugin

$SUDOERS_RULE
EOF

# Set proper permissions
sudo chmod 0440 "$SUDOERS_FILE"
sudo chown root:wheel "$SUDOERS_FILE"

# Verify the sudoers file is valid
echo "Verifying configuration..."
if sudo visudo -c -f "$SUDOERS_FILE" 2>/dev/null; then
    echo -e "${GREEN}Configuration verified successfully!${NC}"
else
    echo -e "${RED}Error: Invalid sudoers configuration. Removing...${NC}"
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

# Test that it works
echo ""
echo "Testing configuration..."
if sudo -n "$EJECT_BINARY" --version >/dev/null 2>&1; then
    echo -e "${GREEN}Success! The eject tool can now run without password prompts.${NC}"
else
    echo -e "${YELLOW}Note: Configuration saved. Please restart Terminal and try again.${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}  Setup Complete!${NC}"
echo "=========================================="
echo ""
echo "You can now use the Eject All Disks button in Stream Deck."
echo "The disks will eject without requiring a password prompt."
echo ""
echo "To remove this configuration later, run:"
echo "  sudo rm /etc/sudoers.d/eject-disks"
echo ""
