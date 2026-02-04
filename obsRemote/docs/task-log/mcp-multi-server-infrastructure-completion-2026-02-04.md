# MCP Multi-Server Infrastructure — COMPLETED

**Date:** 2026-02-04
**Task:** Enable multiple MCP servers behind a single OAuth-protected endpoint

---

## Overview

Successfully implemented path-based routing to support multiple MCP servers from a single domain, all sharing the same OAuth authentication. This creates a scalable pattern for adding new MCP servers without duplicating authentication infrastructure.

---

## What Changed

### 1. JWT Validator v1.2.0 — Multi-Backend Routing
**File:** `jwt-validator/main.go`
**Image:** `registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0`

- **Added:** `MCPBackendObsidianURL` config field
- **Added:** `getBackendURL()` function for path-based routing
- **Added:** `/mcp/obsidian` route handler
- **Routing Logic:**
  - `/mcp` → `organizerserver:3000/mcp` (inventory tools)
  - `/mcp/obsidian` → `mcp-obsidian:3000/mcp` (vault tools)

### 2. Nginx Configuration — New Location Block
**File:** `obsRemote/custom_server.conf`

- **Added:** `location = /mcp/obsidian` block
- Routes through JWT validator with same CORS/SSE settings as `/mcp`
- `auth_basic off` to use OAuth instead

### 3. Docker Compose — mcp-obsidian Service
**File:** `obsRemote/run_obsidian_remote.yml`

- **Fixed:** Service was incorrectly placed after `networks:` section
- **Fixed:** Network name `obsremote_network` → `obsidian_network`
- **Added:** `command: ["node", "src/index.js", "/obsidian"]` to set vault path
- **Added:** `MCP_BACKEND_OBSIDIAN_URL` to jwt-validator service

### 4. Environment Variables
**File:** `obsRemote/dev/docker-compose.env`

- **Added:** `MCP_OBSIDIAN_VERSION=1.0.2`
- **Updated:** `JWT_VALIDATOR_VERSION=1.1.0` → `1.2.0`

### 5. mcp-obsidian v1.0.2 — Streaming Fix (by mcp-obsidian agent)

Fixed critical bug where MCP server instance was shared across sessions, causing responses to be sent to wrong transport and connections to hang.

---

## Architecture

```
Claude Desktop/Web
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  alanhoangnguyen.com (Nginx)                                 │
│  ├── /.well-known/oauth-authorization-server (shared)        │
│  ├── /mcp            → jwt-validator:9000/mcp                │
│  └── /mcp/obsidian   → jwt-validator:9000/mcp/obsidian       │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  JWT Validator (jwt_validator:9000)                          │
│  ├── Validates OAuth token against Keycloak JWKS             │
│  ├── /mcp          → organizerserver:3000/mcp                │
│  └── /mcp/obsidian → mcp-obsidian:3000/mcp                   │
└──────────────────────────────────────────────────────────────┘
        │                           │
        ▼                           ▼
┌─────────────────────┐   ┌─────────────────────┐
│  organizerserver    │   │  mcp-obsidian       │
│  :3000/mcp          │   │  :3000/mcp          │
│  7 inventory tools  │   │  9 vault tools      │
└─────────────────────┘   └─────────────────────┘
```

---

## MCP Servers Deployed

### 1. Inventory Server (organizerserver)
**URL:** `https://alanhoangnguyen.com/mcp`
**Tools:**
- `inventory_get_inventory` - Get complete inventory overview
- `inventory_get_container` - Get contents of specific container
- `inventory_find_location` - Find where an item is located
- `inventory_get_containers` - List all containers
- `inventory_create_items` - Add items to a container
- `inventory_delete_items` - Remove items from a container
- `inventory` - Natural language inventory command

### 2. Obsidian Vault Server (mcp-obsidian)
**URL:** `https://alanhoangnguyen.com/mcp/obsidian`
**Tools:**
- `search-vault` - Search content with boolean operators (AND, OR, NOT)
- `search-by-title` - Search by H1 title
- `list-notes` - List all notes in vault/directory
- `read-note` - Read note content
- `write-note` - Create or update notes
- `delete-note` - Delete notes
- `search-by-tags` - Search by frontmatter/inline tags
- `get-note-metadata` - Get frontmatter and metadata
- `discover-mocs` - Discover Maps of Content (hub notes)

---

## Authentication

### Shared OAuth Configuration
All MCP servers share the same Keycloak OAuth setup:

| Field | Value |
|-------|-------|
| Discovery URL | `https://alanhoangnguyen.com/.well-known/oauth-authorization-server` |
| Client ID | `chatgpt-mcp-client` |
| Client Secret | `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu` |
| Authorization Endpoint | `https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth` |
| Token Endpoint | `https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token` |

### Test User
| Field | Value |
|-------|-------|
| Username | `mcp-oauth-test` |
| Password | `McpTest2026` |

---

## Adding New MCP Servers

To add a new MCP server (e.g., `/mcp/calendar`):

### 1. JWT Validator
Add new config and route in `main.go`:
```go
// Config
MCPBackendCalendarURL string
// loadConfig()
MCPBackendCalendarURL: getEnv("MCP_BACKEND_CALENDAR_URL", "http://mcp-calendar:3000"),
// Route
mux.Handle("/mcp/calendar", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))
// getBackendURL()
if strings.HasPrefix(path, "/mcp/calendar") {
    return v.config.MCPBackendCalendarURL + "/mcp"
}
```

### 2. Nginx
Add location block in `custom_server.conf`:
```nginx
location = /mcp/calendar {
    auth_basic off;
    proxy_pass http://jwt-validator:9000/mcp/calendar;
    # ... same settings as /mcp/obsidian
}
```

### 3. Docker Compose
Add service in `run_obsidian_remote.yml`:
```yaml
mcp-calendar:
  image: registry.alanhoangnguyen.com/admin/mcp-calendar:${MCP_CALENDAR_VERSION:-latest}
  # ...
```

Add env var to jwt-validator:
```yaml
- MCP_BACKEND_CALENDAR_URL=http://mcp-calendar:3000
```

### 4. Deploy
```bash
# Rebuild and push jwt-validator
cd jwt-validator && docker build -t registry.../jwt-validator:X.Y.Z . && docker push ...

# Deploy
cd obsRemote && source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml pull
docker compose -f run_obsidian_remote.yml up -d --force-recreate jwt-validator mcp-calendar
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload
```

---

## Test Results

### Initialize + tools/list Test
```bash
# Initialize
curl -X POST "https://alanhoangnguyen.com/mcp/obsidian" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize",...}'

# Response (immediate, no hang):
HTTP/2 200
mcp-session-id: b3d940c4-400d-4f9a-bf72-6962692f3b9d
event: message
data: {"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{"listChanged":false}},...}

# tools/list with session
curl -X POST "https://alanhoangnguyen.com/mcp/obsidian" \
  -H "Mcp-Session-Id: b3d940c4-400d-4f9a-bf72-6962692f3b9d" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list",...}'

# Response: 9 tools returned successfully
```

---

## Files Modified

| File | Change |
|------|--------|
| `jwt-validator/main.go` | Added multi-backend routing (v1.2.0) |
| `obsRemote/custom_server.conf` | Added `/mcp/obsidian` location block |
| `obsRemote/run_obsidian_remote.yml` | Fixed mcp-obsidian service, added env vars |
| `obsRemote/dev/docker-compose.env` | Added MCP_OBSIDIAN_VERSION, updated JWT_VALIDATOR_VERSION |

---

## Issues Resolved

### 1. mcp-obsidian Connection Hang
**Cause:** Single MCP server instance shared across all sessions. Responses sent to first transport only.
**Fix:** mcp-obsidian v1.0.2 creates separate server per session.

### 2. Wrong Vault Path
**Cause:** Dockerfile hardcoded `/vault` but mount was at `/obsidian`
**Fix:** Added `command:` override in docker-compose to pass correct path.

### 3. Compose Syntax Error
**Cause:** mcp-obsidian service placed after `networks:` section
**Fix:** Moved service before networks declaration.

---

## Status

**COMPLETED** — Multi-MCP server infrastructure deployed and tested. Both inventory and obsidian servers accessible via OAuth-protected endpoints.

---

**Completed:** 2026-02-04
**Components:** JWT Validator v1.2.0, mcp-obsidian v1.0.2
**Tested:** Initialize, tools/list, session management all working
