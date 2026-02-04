# MCP Obsidian Production Deployment Guide

**Date:** 2026-02-03
**Version:** 1.0.0
**Status:** Ready for deployment

---

## Overview

This document describes the deployment of mcp-obsidian with Streamable HTTP transport to the production environment at `alanhoangnguyen.com`.

## Architecture Changes

### Current State
- Legacy SSE transport (`/sse` + `/message` endpoints)
- No production deployment

### Target State
- Streamable HTTP transport (`/mcp` single endpoint)
- Deployed behind JWT validator with OAuth
- Accessible at `https://alanhoangnguyen.com/obsidian-mcp`

---

## Required Docker Compose Changes

### 1. Add mcp-obsidian Service

Add to `/root/Orchestration/obsRemote/run_obsidian_remote.yml` **before** the `networks:` section:

```yaml
  mcp-obsidian:
    image: registry.alanhoangnguyen.com/admin/mcp-obsidian:${MCP_OBSIDIAN_VERSION:-latest}
    container_name: mcp-obsidian
    restart: unless-stopped
    networks:
      - obsidian_network
    environment:
      - PORT=3000
      - VAULT_PATH=/vault
      - ALLOWED_ORIGINS=*
    volumes:
      - /root/vault:/vault:ro
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
```

**Notes:**
- Uses `obsidian_network` (not `obsremote_network`)
- Vault path: `/root/vault` (adjust to actual vault location)
- Image pulled from private registry

---

## JWT Validator Route Configuration

### 2. Add Route to JWT Validator

Edit `/root/Orchestration/jwt-validator/main.go` to add:

```go
http.HandleFunc("/obsidian-mcp", func(w http.ResponseWriter, r *http.Request) {
    handleProtectedRoute(w, r, "http://mcp-obsidian:3000/mcp")
})
```

**Rebuild and deploy JWT validator:**

```bash
cd /root/Orchestration/jwt-validator
docker build -t registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0 .
docker push registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0
```

**Update compose version:**
```yaml
jwt-validator:
  image: registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0
```

---

## Nginx Configuration

### 3. Add Nginx Location Block

Edit `/root/Orchestration/obsRemote/custom_server.conf` in the 443 server block:

```nginx
# MCP Obsidian Server Endpoint
location /obsidian-mcp {
    proxy_pass http://jwt_validator:9000/obsidian-mcp;

    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Authorization $http_authorization;

    # Disable buffering for streaming
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;

    # CORS
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept, Mcp-Session-Id" always;
    add_header Access-Control-Expose-Headers "Mcp-Session-Id" always;

    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

**Test and reload nginx:**
```bash
docker exec nginx_proxy_manager nginx -t
docker exec nginx_proxy_manager nginx -s reload
```

---

## Deployment Steps

### 4. Deploy mcp-obsidian

```bash
# SSH to production
ssh root@digitalocean

cd /root/Orchestration/obsRemote

# Set version (or use latest)
export MCP_OBSIDIAN_VERSION=1.0.1

# Pull and start
docker compose -f run_obsidian_remote.yml pull mcp-obsidian
docker compose -f run_obsidian_remote.yml up -d mcp-obsidian

# Check logs
docker logs mcp-obsidian

# Healthcheck
docker compose -f run_obsidian_remote.yml exec mcp-obsidian wget -qO- http://localhost:3000/health
```

### 5. Restart JWT Validator (if route was added)

```bash
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate jwt_validator
```

---

## Verification

### 6. Test with OAuth Token

```bash
# Get OAuth token
TOKEN=$(curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
  -d "username=mcp-oauth-test" \
  -d "password=McpTest2026" \
  -d "scope=openid" | jq -r '.access_token')

# Test initialize
curl -s -D /tmp/headers.txt -X POST "https://alanhoangnguyen.com/obsidian-mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# Extract session ID
SESSION_ID=$(grep -i "mcp-session-id:" /tmp/headers.txt | awk '{print $2}' | tr -d '\r\n')
echo "Session ID: $SESSION_ID"

# Test tools/list
curl -s -X POST "https://alanhoangnguyen.com/obsidian-mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## Rollback Plan

If issues occur:

```bash
# Stop mcp-obsidian
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml stop mcp-obsidian
docker compose -f run_obsidian_remote.yml rm mcp-obsidian

# Remove nginx location block from custom_server.conf
# Reload nginx
```

---

## Infrastructure Reference

| Component | Location/URL |
|-----------|--------------|
| OAuth Discovery | `https://alanhoangnguyen.com/.well-known/oauth-authorization-server` |
| Token Endpoint | `https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token` |
| MCP Endpoint | `https://alanhoangnguyen.com/obsidian-mcp` |
| Registry | `registry.alanhoangnguyen.com/admin/mcp-obsidian` |
| Compose File | `/root/Orchestration/obsRemote/run_obsidian_remote.yml` |
| Nginx Config | `/root/Orchestration/obsRemote/custom_server.conf` |
| JWT Validator | `/root/Orchestration/jwt-validator/main.go` |

---

## Client Registration (Claude.ai)

**Public URL:** `https://alanhoangnguyen.com/obsidian-mcp`

**OAuth Credentials:**
- Client ID: `chatgpt-mcp-client`
- Client Secret: `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu`

Claude will automatically:
1. Fetch OAuth discovery document
2. Redirect to Keycloak for authentication
3. Exchange code for tokens
4. Call MCP server with Bearer token
