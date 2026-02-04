#!/bin/bash
# Registry Push Test and Monitor Script
# This script helps diagnose push issues and monitors the registry during push operations

set -e

echo "======================================"
echo "Registry Push Test & Monitor"
echo "======================================"
echo ""

# Check if we're on production or build server
if [ ! -f "/root/Orchestration/obsRemote/run_obsidian_remote.yml" ]; then
    echo "⚠️  This appears to be the build server"
    echo "Run this script on the PRODUCTION server to monitor pushes"
    echo ""
    echo "On build server, follow these steps:"
    echo "1. Clear Docker registry cache:"
    echo "   docker logout registry.alanhoangnguyen.com"
    echo "   rm -rf ~/.docker/manifests/registry.alanhoangnguyen.com* 2>/dev/null"
    echo ""
    echo "2. Re-login:"
    echo "   docker login registry.alanhoangnguyen.com"
    echo ""
    echo "3. Push with verbose output:"
    echo "   docker push registry.alanhoangnguyen.com/admin/conversationalist:1.0.30"
    echo ""
    echo "WATCH FOR: Layers 02d7611c4eae, 8715e552fa13, 9c27bc7ba63d"
    echo "Should show 'Pushing' NOT 'Layer already exists'"
    exit 0
fi

echo "✅ Running on production server"
echo ""

# Function to monitor registry logs
monitor_logs() {
    echo "📊 Monitoring registry logs (Ctrl+C to stop)..."
    echo "Looking for PUT/POST operations (blob uploads)..."
    echo ""
    docker logs -f docker_registry 2>&1 | grep --line-buffered -E "PUT|POST|blob|error" | while read line; do
        if echo "$line" | grep -q "error"; then
            echo "🔴 $line"
        elif echo "$line" | grep -q "PUT.*blob"; then
            echo "🟢 $line"
        else
            echo "   $line"
        fi
    done
}

# Menu
echo "Choose an option:"
echo "1. Monitor registry logs during push"
echo "2. Check registry health"
echo "3. Test registry can accept writes"
echo "4. View recent registry activity"
echo "5. Show instructions for build server"
echo ""
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        echo ""
        echo "🚀 Start your push from the build server NOW"
        echo "   (in another terminal window)"
        echo ""
        sleep 2
        monitor_logs
        ;;
    2)
        echo ""
        echo "🏥 Registry Health Check:"
        echo "------------------------"
        docker ps --filter name=docker_registry --format "Status: {{.Status}}"
        echo ""
        echo "Endpoint test:"
        curl -s -I https://registry.alanhoangnguyen.com/v2/ | head -1
        echo ""
        echo "Disk space:"
        df -h /root/Orchestration/obsRemote/registry/data | tail -1
        echo ""
        echo "Recent errors:"
        docker logs docker_registry --tail 100 | grep -i error | tail -5 || echo "No recent errors"
        ;;
    3)
        echo ""
        echo "🧪 Testing write capability..."
        TEST_FILE="/root/Orchestration/obsRemote/registry/data/.write-test-$(date +%s)"
        if echo "test" > "$TEST_FILE" 2>/dev/null; then
            rm "$TEST_FILE"
            echo "✅ Registry storage is writable"
        else
            echo "❌ Registry storage write FAILED"
            ls -ld /root/Orchestration/obsRemote/registry/data
        fi
        echo ""
        echo "Container permissions:"
        docker exec docker_registry ls -la /var/lib/registry | head -5
        ;;
    4)
        echo ""
        echo "📜 Recent Registry Activity:"
        echo "----------------------------"
        docker logs docker_registry --tail 50 | grep -E "PUT|POST|GET.*blob" | tail -20
        ;;
    5)
        echo ""
        echo "📋 Instructions for Build Server:"
        echo "==================================
"
        echo "The registry has been optimized with:"
        echo "  ✅ HTTP/2 disabled (fixes silent upload failures)"
        echo "  ✅ 30-minute timeouts (handles large blobs)"
        echo "  ✅ HTTP secret configured (prevents upload issues)"
        echo "  ✅ Enhanced logging enabled"
        echo ""
        echo "Steps to push from build server:"
        echo ""
        echo "1. Clear Docker's registry cache:"
        echo "   docker logout registry.alanhoangnguyen.com"
        echo "   rm -rf ~/.docker/manifests/registry.alanhoangnguyen.com*"
        echo ""
        echo "2. Re-login:"
        echo "   docker login registry.alanhoangnguyen.com"
        echo "   # Use credentials: admin / [password]"
        echo ""
        echo "3. Push the image:"
        echo "   docker push registry.alanhoangnguyen.com/admin/conversationalist:1.0.30"
        echo ""
        echo "4. Watch the output for these layers:"
        echo "   - 02d7611c4eae (should show 'Pushing...' not 'Layer already exists')"
        echo "   - 8715e552fa13 (should show 'Pushing...' not 'Layer already exists')"
        echo "   - 9c27bc7ba63d (should show 'Pushing...' not 'Layer already exists')"
        echo ""
        echo "5. If push completes, test pull on production:"
        echo "   docker pull registry.alanhoangnguyen.com/admin/conversationalist:1.0.30"
        echo ""
        echo "If push still fails, the blobs may be corrupted on build server."
        echo "Alternative: Use docker save/load to transfer directly."
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
