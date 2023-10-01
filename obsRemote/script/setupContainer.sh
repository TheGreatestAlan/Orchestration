#!/bin/bash

# Define the paths
OBSIDIAN_VAULTS="$HOME/obsidian/vaults"
OBSIDIAN_CONFIG="$HOME/obsidian/config"

# Write to /etc/environment
echo "OBSIDIAN_VAULTS=$OBSIDIAN_VAULTS" | sudo tee -a /etc/environment
echo "OBSIDIAN_CONFIG=$OBSIDIAN_CONFIG" | sudo tee -a /etc/environment

echo "Environment variables set successfully."

