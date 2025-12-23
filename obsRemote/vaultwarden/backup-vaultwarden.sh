#!/bin/bash
# Vaultwarden Backup Script

set -e

BACKUP_DIR="/var/backups/vaultwarden"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/vaultwarden_backup_$DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
echo "Creating backup: $BACKUP_FILE"
cd /root/Orchestration/obsRemote
tar -czf "$BACKUP_FILE" vaultwarden/vw-data/

# Keep only last 30 days of backups
find "$BACKUP_DIR" -name "vaultwarden_backup_*.tar.gz" -mtime +30 -delete

echo "Backup complete: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
