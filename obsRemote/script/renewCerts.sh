#!/bin/bash
#BEFORE YOU RUN THIS YOU NEED TO STOP THE DOCKER CONTAINERS

set -euo pipefail

# 1) Define the target directory explicitly
TARGET_DIR="/root/Orchestration/obsRemote/npm/letsencrypt"

# 2) Renew all certificates
echo "Renewing certificates with Certbot..."
sudo certbot renew --standalone --deploy-hook "true"
echo "Certificates renewed successfully."
echo "-----------------------------------"

# 3) Ensure target directories exist
mkdir -p "$TARGET_DIR/live"
mkdir -p "$TARGET_DIR/archive"

# 4) Define source directories
SOURCE_DIR_LIVE="/etc/letsencrypt/live"
SOURCE_DIR_ARCHIVE="/etc/letsencrypt/archive"

# 5) Copy (sync) the contents of "live" and "archive" directories
#    (no --delete, so we do NOT remove anything that might already be in the target)
echo "Copying certificate files to $TARGET_DIR ..."
rsync -av "$SOURCE_DIR_LIVE/" "$TARGET_DIR/live/"
rsync -av "$SOURCE_DIR_ARCHIVE/" "$TARGET_DIR/archive/"

# 6) Set permissions so only the owner can read/write
chmod -R 600 "$TARGET_DIR"

echo "All cert files copied to $TARGET_DIR."
echo "Done!"

