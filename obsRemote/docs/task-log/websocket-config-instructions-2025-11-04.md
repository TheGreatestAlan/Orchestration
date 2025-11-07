# WebSocket Nginx Configuration - Claude Instructions

**Created**: 2025-11-04
**Purpose**: Fix WebSocket 404 error for InventoryAgent testing
**File**: /root/Orchestration/obsRemote/custom_server.conf
**Location**: Place this in `/root/Orchestration/obsRemote/docs/task-log/`

## Current Issue
- WebSocket endpoint `/ws` returning 404
- InventoryAgent deployed successfully but WebSocket testing blocked
- nginx missing WebSocket location block configuration

## Quick Status Check
```bash
# Check current nginx config
docker exec obsremote-nginx-1 cat /etc/nginx/conf.d/custom_server.conf

# Test WebSocket (should fail with 404)
curl -i https://helper.alanhoangnguyen.com/ws

# Check agent-server is running
docker logs obsremote-agent-server-1 --tail 10 | grep InventoryAgent
```

## Safe Configuration Steps

### Step 1: Backup Current Config
```bash
cd /root/Orchestration/obsRemote
cp custom_server.conf custom_server.conf.backup.$(date +%Y%m%d_%H%M%S)
ls -la custom_server.conf.backup.*
```

### Step 2: Show Current Config
```bash
echo "=== CURRENT NGINX CONFIG ==="
cat custom_server.conf
echo "=== END CONFIG ==="
```

### Step 3: Add WebSocket Location Block
The config needs this location block added:

```nginx
location /ws {
    proxy_pass http://agent-server:12346;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 86400;
}
```

### Step 4: Edit Configuration
```bash
# Use nano or preferred editor
nano custom_server.conf

# Add the location /ws block in the server context
# Usually after other location blocks
```

### Step 5: Validate and Reload
```bash
# Test nginx configuration
docker exec obsremote-nginx-1 nginx -t

# If test passes, reload nginx
docker exec obsremote-nginx-1 nginx -s reload

# Check nginx logs for errors
docker logs obsremote-nginx-1 --tail 20
```

### Step 6: Test WebSocket
```bash
# Test WebSocket endpoint
curl -i https://helper.alanhoangnguyen.com/ws

# Should return 101 Switching Protocols instead of 404
```

## Full Example Configuration
Here's what the complete server block should look like:

```nginx
server {
    listen 443 ssl http2;
    server_name helper.alanhoangnguyen.com;

    # SSL configuration (existing)
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # Existing locations...

    # Add this WebSocket location block
    location /ws {
        proxy_pass http://agent-server:12346;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # Existing /agent/ location (should already exist)
    location /agent/ {
        proxy_pass http://agent-server:8080/;
        # ... existing config ...
    }
}
```

## Testing Commands

### Basic WebSocket Test
```bash
# Install wscat if needed
npm install -g wscat

# Test WebSocket connection
wscat -c wss://helper.alanhoangnguyen.com/ws

# Should connect successfully
```

### Production Inventory Test
```bash
# From local client_app directory after fix
python test_production_inventory.py
```

### Monitor Logs
```bash
# Watch nginx access logs
docker logs obsremote-nginx-1 -f | grep -E "ws|WS"

# Watch agent-server logs
docker logs obsremote-agent-server-1 -f | grep InventoryAgent
```

## Rollback Plan
If issues arise:

```bash
# Restore backup
cd /root/Orchestration/obsRemote
ls custom_server.conf.backup.*  # Find latest backup
cp custom_server.conf.backup.[TIMESTAMP] custom_server.conf

# Reload nginx
docker exec obsremote-nginx-1 nginx -t
docker exec obsremote-nginx-1 nginx -s reload
```

## Current Infrastructure Context
- Agent Server: obsremote-agent-server-1 (running, port 12346)
- Nginx: obsremote-nginx-1 (needs config update)
- Network: obsremote_obsidian_network
- InventoryAgent: Version 1.0.25 deployed and working via REST

## Success Criteria
- [ ] WebSocket endpoint returns 101 Switching Protocols
- [ ] InventoryAgent operations work via WebSocket
- [ ] No nginx configuration errors
- [ ] Both REST and WebSocket endpoints functional

## Notes for Claude
- InventoryAgent is already deployed and working
- This is purely an nginx configuration fix
- REST API at /agent/ should continue working
- WebSocket at /ws needs to proxy to agent-server:12346
- Test thoroughly before considering complete

## To Deploy These Instructions
When SSH access is restored:
```bash
# Create directory if needed
ssh root@digitalocean "mkdir -p /root/Orchestration/obsRemote/docs/task-log"

# Copy this file to droplet
scp websocket-config-instructions-droplet.md root@digitalocean:/root/Orchestration/obsRemote/docs/task-log/websocket-config-instructions-2025-11-04.md
```