#!/bin/bash
set -euo pipefail

# 1) Define the target directory explicitly
TARGET_DIR="/root/Orchestration/obsRemote/npm/letsencrypt"

# 2) Ensure target directories exist
mkdir -p "$TARGET_DIR/live"
mkdir -p "$TARGET_DIR/archive"

# 3) Define source directories
SOURCE_DIR_LIVE="/etc/letsencrypt/live"
SOURCE_DIR_ARCHIVE="/etc/letsencrypt/archive"

# 4) Copy (sync) the contents of "live" and "archive" directories
#    (We do NOT use --delete so nothing in the target gets removed)
echo "Copying certificate files to $TARGET_DIR ..."
rsync -av "$SOURCE_DIR_LIVE/" "$TARGET_DIR/live/"
rsync -av "$SOURCE_DIR_ARCHIVE/" "$TARGET_DIR/archive/"

# 5) Set file permissions so only the owner can read/write
chmod -R 600 "$TARGET_DIR"

echo "All cert files copied to $TARGET_DIR."
echo "Done!"

