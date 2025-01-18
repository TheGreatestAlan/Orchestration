#!/bin/bash

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define the target directory relative to the script's location
TARGET_DIR="$SCRIPT_DIR/../npm/letsencrypt"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Define the source directories
SOURCE_DIR_LIVE="/etc/letsencrypt/live"
SOURCE_DIR_ARCHIVE="/etc/letsencrypt/archive"

# Copy the entire live directory
rsync -av --delete "$SOURCE_DIR_LIVE/" "$TARGET_DIR/live/"

# Copy the entire archive directory
rsync -av --delete "$SOURCE_DIR_ARCHIVE/" "$TARGET_DIR/archive/"

# Set appropriate permissions for the copied files
chmod -R 600 "$TARGET_DIR"

echo "Entire 'live' and 'archive' directories copied to $TARGET_DIR" 

