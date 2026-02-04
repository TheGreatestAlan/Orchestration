#!/bin/bash

# Vaultwarden Deployment Script
# One-command production deployment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Vaultwarden Production Deployment ===${NC}"
echo ""

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Warning: Running as root. Consider using a regular user with docker group.${NC}"
fi

# Download and run the setup script
if [ -f "setup-vaultwarden.sh" ]; then
    echo "Using local setup script..."
    ./setup-vaultwarden.sh
else
    echo "Downloading Vaultwarden setup script..."
    curl -fsSL https://raw.githubusercontent.com/your-repo/vaultwarden-setup/main/setup-vaultwarden.sh | bash
fi

echo ""
echo -e "${GREEN}✅ Deployment initiated!${NC}"
echo "Follow the prompts to configure your Vaultwarden instance."