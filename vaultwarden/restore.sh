#!/bin/bash

# Vaultwarden Restore Script
# Restores from a backup file

BACKUP_DIR="./backups"
DATA_DIR="./vw-data"

# Check if backup file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup-file>"
    echo ""
    echo "Available backups:"
    ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    # Try in backup directory
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "❌ Backup file not found: $1"
        exit 1
    fi
fi

echo "⚠️  This will replace all current Vaultwarden data!"
read -p "Are you sure you want to continue? (yes/no): " -r

if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Create backup of current data first
echo "Creating safety backup of current data..."
SAFETY_BACKUP="$BACKUP_DIR/safety-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$SAFETY_BACKUP" "$DATA_DIR" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Safety backup created: $SAFETY_BACKUP"
fi

# Stop Vaultwarden
echo "Stopping Vaultwarden..."
docker compose down

# Remove current data
echo "Removing current data..."
rm -rf "$DATA_DIR"

# Extract backup
echo "Extracting backup..."
tar -xzf "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Backup extracted successfully"

    # Start Vaultwarden
    echo "Starting Vaultwarden..."
    docker compose up -d

    # Wait a moment and check status
    sleep 5
    ./monitor.sh

    echo ""
    echo "✅ Restore complete!"
    echo "🌐 Access your vault at: http://localhost:8080"
else
    echo "❌ Restore failed!"
    echo "You can recover from the safety backup: $SAFETY_BACKUP"
    exit 1
fi