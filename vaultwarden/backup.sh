#!/bin/bash

# Vaultwarden Backup Script
# Creates timestamped backups of Vaultwarden data

BACKUP_DIR="./backups"
DATA_DIR="./vw-data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vaultwarden_backup_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=30

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    echo "❌ Error: Data directory $DATA_DIR not found"
    exit 1
fi

# Create backup
echo "Creating backup..."
tar -czf "$BACKUP_DIR/$BACKUP_NAME" "$DATA_DIR" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup created: $BACKUP_DIR/$BACKUP_NAME"

    # Show backup size
    SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME" | cut -f1)
    echo "📦 Backup size: $SIZE"

    # Clean up old backups (keep last 30 days)
    echo "Cleaning up old backups..."
    find "$BACKUP_DIR" -name "vaultwarden_backup_*.tar.gz" -mtime +$RETENTION_DAYS -delete

    # List remaining backups
    echo ""
    echo "Available backups:"
    ls -lht "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10

else
    echo "❌ Backup failed!"
    exit 1
fi

# Optional: Upload to S3 (configure AWS CLI first)
# aws s3 cp "$BACKUP_DIR/$BACKUP_NAME" s3://your-bucket/vaultwarden/

echo ""
echo "💡 To restore from backup:"
echo "   docker compose down"
echo "   rm -rf $DATA_DIR"
echo "   tar -xzf $BACKUP_DIR/$BACKUP_NAME"
echo "   docker compose up -d"