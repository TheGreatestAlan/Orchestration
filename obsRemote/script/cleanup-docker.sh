#!/bin/bash
# Docker cleanup script - removes unused images and runs registry garbage collection
# This script is safe to run regularly as it only removes unused resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Docker Cleanup Started: $(date) ==="

# Source environment variables
source script/sourceEnv.sh

# Step 1: Remove dangling images (untagged)
echo "[1/4] Removing dangling images..."
docker images -f "dangling=true" -q | xargs -r docker rmi -f || echo "No dangling images to remove"

# Step 2: Remove unused images older than 7 days (keeps recent builds)
echo "[2/4] Removing unused images older than 7 days..."
docker image prune -a --filter "until=168h" --force

# Step 3: Prune Docker system (containers, networks, build cache)
echo "[3/4] Pruning Docker system..."
docker system prune -f

# Step 4: Run registry garbage collection
echo "[4/4] Running registry garbage collection..."
docker compose -f run_obsidian_remote.yml exec -T docker-registry bin/registry garbage-collect /etc/docker/registry/config.yml --delete-untagged 2>&1 | grep -E "(marking|deleting|eligible)" || echo "Registry GC completed"

# Report disk usage
echo ""
echo "=== Cleanup Summary ==="
echo "Disk usage:"
df -h / | tail -1
echo ""
echo "Registry size:"
docker compose -f run_obsidian_remote.yml exec -T docker-registry du -sh /var/lib/registry/docker 2>&1 | grep -v "^time=" | grep "G"
echo ""
echo "=== Docker Cleanup Completed: $(date) ==="
