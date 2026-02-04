#!/bin/bash

# Production backup script

BACKUP_DIR="/var/backups/vaultwarden"
DATA_DIR="./vw-data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vaultwarden_prod_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
tar -czf "$BACKUP_DIR/$BACKUP_NAME" "$DATA_DIR" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup created: $BACKUP_DIR/$BACKUP_NAME"

    # Clean up old backups
    find "$BACKUP_DIR" -name "vaultwarden_prod_*.tar.gz" -mtime +$RETENTION_DAYS -delete

    # Optional: Upload to S3
    # aws s3 cp "$BACKUP_DIR/$BACKUP_NAME" s3://your-bucket/vaultwarden/
else
    echo "❌ Backup failed!"
    exit 1
fi