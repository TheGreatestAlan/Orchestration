# MCP OAuth Infrastructure Configuration for Claude.ai
**Production Agent Work - OAuth & Infrastructure Changes**

**Date:** 2026-02-03
**Priority:** HIGH - Required for Claude.ai integration
**Owner:** Production Agent
**Status:** BLOCKED - Waiting for local agent transport migration
**Depends On:** Local agent must complete Streamable HTTP migration first

---

## Executive Summary

To enable Claude.ai MCP integration, the production infrastructure requires OAuth and routing configuration changes. These changes can only be applied **after** the local agent migrates the MCP server from SSE to Streamable HTTP transport.

**Critical Dependency:** This work is **blocked** until the local agent completes the transport migration. Do not proceed until organizerserver is deployed with Streamable HTTP support.

---

## Feature Description

### What is Claude MCP Integration?

Claude.ai (Web, Desktop, iOS) users can add custom MCP servers as "connectors" to extend Claude's capabilities. For our inventory MCP server, this means:

- Claude users authenticate via OAuth 2.1
- Claude discovers server capabilities via metadata endpoints
- Claude can invoke 7 inventory management tools
- All communication secured via OAuth tokens

### Current State

**OAuth chain is partially working:**
- ✅ Keycloak running at auth.alanhoangnguyen.com
- ✅ JWT validator v1.0.9 validates tokens
- ✅ Nginx routes to JWT validator
- ✅ MCP server has OAuth config

**But incompatible with Claude:**
- ❌ Discovery endpoint at wrong location
- ❌ Claude callback URLs not whitelisted in Keycloak
- ❌ Nginx routes to SSE endpoints (wrong transport)
- ❌ MCP server uses SSE transport (deprecated)

### Target State

**After local agent completes transport migration AND production completes this work:**
- ✅ Discovery endpoint at `/.well-known/oauth-authorization-server`
- ✅ Claude callback URLs whitelisted in Keycloak
- ✅ Nginx routes to single `/mcp` endpoint
- ✅ MCP server uses Streamable HTTP transport
- ✅ Claude Desktop can connect and use tools

---

## The Problem

### Why OAuth Wasn't Working

After extensive debugging in January 2026, we discovered the root cause:

**Transport Layer Incompatibility:**
- We built an SSE-based MCP server (legacy transport)
- Claude requires Streamable HTTP transport (current standard)
- OAuth worked, but transport layer was incompatible
- This caused "zero tools" and connection issues

**OAuth Issues (Secondary):**
- Discovery endpoint at wrong path for Claude
- Claude callback URLs not in Keycloak whitelist
- Custom scopes (inventory:read, inventory:write) couldn't be assigned

Sources:
- https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers

### Symptoms Observed (January 2026)

1. **ChatGPT Testing:**
   - OAuth authentication succeeded
   - SSE connection established but closed within 1 second
   - JWT validator logs: "Error writing SSE response: broken pipe"
   - Result: Zero tools displayed

2. **Authorization Code Testing:**
   - PKCE flow worked correctly
   - Authorization codes generated
   - Token exchange failed: "Code not valid"
   - Root cause unknown (Keycloak server-side issue)

3. **Keycloak Scope Assignment:**
   - Tried 7+ different methods to assign custom scopes
   - All kcadm.sh methods failed
   - Admin password doesn't work for external auth
   - Workaround: Using standard OIDC scopes (openid, email, profile)

---

## What We Tried (January 2026)

### Attempt 1: Fix SSE Streaming in JWT Validator
**Date:** 2026-01-31
**Version:** jwt-validator v1.0.9

**Problem:** JWT validator was buffering SSE responses instead of flushing immediately.

**Fix Applied:**
```go
// jwt-validator/main.go
if isSSE {
    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming not supported", http.StatusInternalServerError)
        return
    }

    buf := make([]byte, 4096)
    for {
        n, err := resp.Body.Read(buf)
        if n > 0 {
            w.Write(buf[:n])
            flusher.Flush()  // Immediate flush
        }
        if err != nil {
            return
        }
    }
}
```

**Result:** Partial improvement, but didn't solve core transport incompatibility.

**Documentation:** `/root/Orchestration/docs/jwt-validator-sse-fix-2026-01-31.md`

### Attempt 2: Configure Host Header Validation
**Date:** 2026-01-31

**Problem:** MCP server returning "421 Invalid Host header"

**Fix Applied:**
```bash
# Environment variables in docker-compose.env
MCP_ALLOWED_HOSTS=alanhoangnguyen.com:*,www.alanhoangnguyen.com:*,localhost:*
MCP_ALLOWED_ORIGINS=https://alanhoangnguyen.com:*,https://www.alanhoangnguyen.com:*
```

**Result:** Resolved 421 errors, but transport incompatibility remained.

**Documentation:** `/root/Orchestration/docs/organizerserver-host-header-issue.md` (local repo)

### Attempt 3: Assign Custom Scopes in Keycloak
**Date:** 2026-01-31

**Problem:** Couldn't assign `inventory:read` and `inventory:write` scopes to chatgpt-mcp-client.

**Methods Tried:**
1. `kcadm.sh update` - "Resource not found"
2. `kcadm.sh create` - "Resource not found"
3. Update entire client JSON - Succeeds but scopes not added
4. Direct REST API calls - Can't get admin token externally
5. Install curl in container - Failed, minimal container image
6. Get container IP for internal API - Network name mismatch

**Workaround:** Using standard OIDC scopes instead:
```bash
MCP_OAUTH_SCOPES=openid,email,profile
```

**Result:** Tokens issued with standard scopes, but semantically incorrect for inventory operations.

**Documentation:** `/root/Orchestration/docs/keycloak-scope-assignment-problem.md` (local repo)

### Attempt 4: OAuth PKCE Flow End-to-End Testing
**Date:** 2026-01-31

**Test:** Automated browser testing with MCP Chrome DevTools

**Results:**
- ✅ PKCE parameters generated correctly
- ✅ Authorization URL loaded successfully
- ✅ User authenticated (mcp-tester-1769879674)
- ✅ Authorization codes received
- ❌ Token exchange failed: "Code not valid"

**PKCE Verification:**
```bash
# Verified cryptographically correct
echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
# Output matched code_challenge exactly
```

**Blocker:** Unknown server-side Keycloak issue. Logs needed but couldn't access.

**Documentation:** `/root/Orchestration/docs/oauth-test-results-2026-01-31.md`

### Key Discovery (2026-02-03)

After all OAuth debugging, discovered the **real root cause:**
- SSE transport is deprecated in MCP spec (as of 2025-03-26)
- Claude requires Streamable HTTP transport for remote servers
- Our entire architecture is incompatible with current MCP clients

**This invalidated OAuth debugging** - OAuth chain works, but transport layer doesn't.

---

## The Fix

### Prerequisites

**MUST be completed before proceeding:**
- [ ] Local agent completes Streamable HTTP migration
- [ ] organizerserver deployed with new transport
- [ ] `/mcp` endpoint responding (not `/sse` and `/messages/`)

**Verify before starting:**
```bash
# Test MCP server directly
docker exec obsremote-organizerserver-1 curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

**Expected response:** Valid JSON-RPC initialize response (not 404 or connection error).

If this fails, **STOP** - local agent work not complete.

---

## Implementation Plan

### Task 1: Solve Keycloak Admin Access

**Priority:** CRITICAL - Blocks all other Keycloak changes

**Problem:** Cannot modify Keycloak client configuration because:
- Admin password in env file doesn't work for external auth
- kcadm.sh authentication works locally but we can't add redirect URIs programmatically
- Web UI login requires the actual admin password

**Options to try:**

#### Option A: Reset Admin Password (Recommended)

```bash
cd /root/Orchestration/obsRemote

# Stop Keycloak
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml stop keycloak

# Start Keycloak with export
docker compose -f run_obsidian_remote.yml run --rm \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD="NewSecurePassword2026!" \
  keycloak start-dev --export-realms

# Update docker-compose.env
vim dev/docker-compose.env
# Change KEYCLOAK_ADMIN_PASSWORD to NewSecurePassword2026!

# Restart Keycloak
docker compose -f run_obsidian_remote.yml up -d keycloak

# Verify login works
curl -X POST "https://auth.alanhoangnguyen.com/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=NewSecurePassword2026!" | jq
```

**Verify:**
- ✅ Token received (not 401 Unauthorized)
- ✅ Can login to web UI at https://auth.alanhoangnguyen.com
- ✅ Can access realm `mcp` and client `chatgpt-mcp-client`

#### Option B: Use Keycloak Web UI

If Option A fails, try the web UI directly:

1. Navigate to https://auth.alanhoangnguyen.com
2. Login as `admin` with current password (try variations in env file)
3. If password doesn't work, see Option C

#### Option C: Postgres Direct Access (RISKY - Last Resort)

```bash
# Connect to Keycloak database
docker exec -it keycloak-db psql -U keycloak -d keycloak

# Query current redirect URIs
SELECT c.client_id, r.value
FROM client c
JOIN client_attributes r ON c.id = r.client_id
WHERE c.client_id = 'chatgpt-mcp-client'
  AND r.name = 'redirect.uris';

# CAREFUL: Direct modification bypasses Keycloak validation
# Only use if other options fail
```

**Warning:** Direct database modification can corrupt Keycloak state. Use only if Options A and B fail.

---

### Task 2: Add Claude Redirect URIs to Keycloak

**Prerequisites:** Task 1 completed (admin access working)

**Redirect URIs to add:**
- `https://claude.ai/api/mcp/auth_callback` (current)
- `https://claude.com/api/mcp/auth_callback` (future-proofing)

**Also verify/keep existing:**
- ChatGPT redirect URIs (if any)
- Test redirect URI: `https://alanhoangnguyen.com/oauth-callback`

#### Method A: Web UI (Recommended if admin access works)

1. Login to https://auth.alanhoangnguyen.com
2. Select realm: `mcp`
3. Navigate: Clients → `chatgpt-mcp-client`
4. Settings tab → Valid redirect URIs section
5. Add:
   - `https://claude.ai/api/mcp/auth_callback`
   - `https://claude.com/api/mcp/auth_callback`
6. Add to "Valid post logout redirect URIs" (same URLs)
7. Add to "Web origins":
   - `https://claude.ai`
   - `https://claude.com`
8. Save

**Verify in UI:**
- ✅ New URLs appear in redirect URIs list
- ✅ No validation errors
- ✅ Save succeeded

#### Method B: kcadm.sh (If we solve the API access issue)

```bash
# Get current client config
docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password "$NEW_PASSWORD"

CLIENT_UUID=$(docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r mcp \
  --fields id,clientId | jq -r '.[] | select(.clientId=="chatgpt-mcp-client") | .id')

# Get current redirect URIs
docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients/$CLIENT_UUID -r mcp \
  | jq -r '.redirectUris' > /tmp/current_redirects.json

# Edit to add Claude URLs
# Then update:
docker exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$CLIENT_UUID -r mcp \
  -s 'redirectUris=["existing-url", "https://claude.ai/api/mcp/auth_callback", "https://claude.com/api/mcp/auth_callback"]'

# Verify
docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients/$CLIENT_UUID -r mcp \
  --fields redirectUris
```

**Verify:**
```bash
# Should show all redirect URIs including new Claude URLs
docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r mcp \
  --fields clientId,redirectUris | jq '.[] | select(.clientId=="chatgpt-mcp-client")'
```

**Expected output:**
```json
{
  "clientId": "chatgpt-mcp-client",
  "redirectUris": [
    "https://alanhoangnguyen.com/oauth-callback",
    "https://claude.ai/api/mcp/auth_callback",
    "https://claude.com/api/mcp/auth_callback"
  ]
}
```

---

### Task 3: Create OAuth Discovery Endpoint

**What:** Add RFC 8414 OAuth authorization server metadata endpoint

**Location:** Nginx configuration at `/.well-known/oauth-authorization-server`

**Why:** Claude fetches this endpoint to discover OAuth endpoints before authentication.

**File to edit:** `/root/Orchestration/obsRemote/custom_server.conf`

**Backup first:**
```bash
cd /root/Orchestration/obsRemote
cp custom_server.conf custom_server.conf.backup-$(date +%Y%m%d_%H%M%S)
```

**Add nginx location block:**

Find the server block for `alanhoangnguyen.com` (port 443) and add:

```nginx
# OAuth Discovery Endpoint for Claude MCP
# RFC 8414: https://datatracker.ietf.org/doc/html/rfc8414
location /.well-known/oauth-authorization-server {
    # Proxy to Keycloak's OIDC discovery endpoint
    # RFC 8414 is compatible with OIDC discovery when issuer has no path component
    proxy_pass https://auth.alanhoangnguyen.com/realms/mcp/.well-known/openid-configuration;

    proxy_set_header Host auth.alanhoangnguyen.com;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Discovery endpoint should be publicly accessible (no auth required)
    # Claude needs to fetch this before authenticating

    # Standard proxy settings
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_cache off;

    # CORS headers for browser-based clients
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;

    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

**Test configuration before reloading:**
```bash
docker exec nginx_proxy_manager nginx -t
```

**Expected output:**
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**Reload nginx if test passes:**
```bash
docker exec nginx_proxy_manager nginx -s reload
```

**Verify endpoint works:**
```bash
curl -s https://alanhoangnguyen.com/.well-known/oauth-authorization-server | jq
```

**Expected response (abbreviated):**
```json
{
  "issuer": "https://auth.alanhoangnguyen.com/realms/mcp",
  "authorization_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth",
  "token_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token",
  "jwks_uri": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/certs",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["plain", "S256"],
  ...
}
```

**Verify required fields present:**
- ✅ `issuer` - Keycloak realm URL
- ✅ `authorization_endpoint` - OAuth authorization URL
- ✅ `token_endpoint` - OAuth token URL
- ✅ `code_challenge_methods_supported` - Includes "S256"

**If response doesn't include required fields,** may need custom JSON instead of proxying Keycloak's endpoint. See "Alternative: Static Discovery Endpoint" below.

---

### Task 4: Update Nginx Routing for Streamable HTTP

**What:** Change from SSE endpoints (`/mcp/sse`, `/mcp/messages/`) to single Streamable HTTP endpoint (`/mcp`)

**Prerequisites:**
- Local agent deployed organizerserver with Streamable HTTP
- Verified `/mcp` endpoint works in container

**File to edit:** `/root/Orchestration/obsRemote/custom_server.conf`

**Backup first:**
```bash
cd /root/Orchestration/obsRemote
cp custom_server.conf custom_server.conf.backup-$(date +%Y%m%d_%H%M%S)
```

**Find and REMOVE old SSE location blocks:**

```nginx
# OLD - REMOVE THESE:
location /mcp/sse { ... }
location /mcp/messages/ { ... }
```

**Add NEW Streamable HTTP location block:**

```nginx
# MCP Streamable HTTP Endpoint
# Supports both POST (requests) and GET (SSE responses)
# Single endpoint for all MCP communication
location /mcp {
    # Forward to JWT validator for OAuth token validation
    proxy_pass http://jwt_validator:9000/mcp;

    # HTTP/1.1 required for proper connection handling
    proxy_http_version 1.1;

    # Connection header handling
    proxy_set_header Connection "";

    # Standard headers
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Forward Authorization header (OAuth tokens)
    proxy_set_header Authorization $http_authorization;

    # Disable buffering for streaming responses
    proxy_buffering off;
    proxy_cache off;

    # Long timeout for persistent connections
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;

    # CORS headers for browser-based MCP clients
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization" always;

    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

**Test configuration:**
```bash
docker exec nginx_proxy_manager nginx -t
```

**Reload if successful:**
```bash
docker exec nginx_proxy_manager nginx -s reload
```

**Verify routing works:**
```bash
# Get a valid OAuth token first (or use API key for testing)
TOKEN="valid-oauth-token-here"

curl -X POST https://alanhoangnguyen.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {"name": "test", "version": "1.0"}
    }
  }'
```

**Expected:**
- ✅ HTTP 200 OK
- ✅ Valid JSON-RPC response
- ✅ No proxy errors

**Check logs if it fails:**
```bash
# Nginx logs
docker logs nginx_proxy_manager --tail 50

# JWT validator logs
docker logs jwt_validator --tail 50

# MCP server logs
./script/see-logs.sh organizerserver
```

---

### Task 5: Update JWT Validator for Streamable HTTP

**What:** JWT validator may need updates to handle Streamable HTTP instead of SSE

**Prerequisites:** Task 4 completed (nginx routing updated)

**Current JWT validator version:** v1.0.9 (SSE streaming fix)

**Check if update needed:**

The current JWT validator has SSE-specific code. Streamable HTTP also uses SSE for responses, so it *might* work as-is, but verification needed.

**Test current JWT validator:**
```bash
# Forward a POST request to /mcp endpoint
# JWT validator should validate token and proxy to organizerserver:3000/mcp

# Check JWT validator logs
docker logs jwt_validator --tail 50
```

**Look for:**
- ✅ "Token validated successfully" - OAuth validation working
- ✅ Request proxied to organizerserver - Forwarding working
- ❌ Any errors about content type or streaming - May need update

**If update needed:**

JWT validator code is at: `/root/Orchestration/jwt-validator/main.go`

**Current SSE detection:**
```go
contentType := resp.Header.Get("Content-Type")
isSSE := strings.Contains(contentType, "text/event-stream")
```

**Should still work for Streamable HTTP** because:
- Streamable HTTP uses SSE for streaming responses
- Content-Type will be "text/event-stream" for GET requests
- Content-Type will be "application/json" for POST responses

**Likely no changes needed unless testing shows issues.**

**If changes are needed:**
1. Modify `/root/Orchestration/jwt-validator/main.go`
2. Update version in code to v1.0.10
3. Build new image:
   ```bash
   cd /root/Orchestration/jwt-validator
   docker build -t registry.alanhoangnguyen.com/admin/jwt-validator:1.0.10 .
   docker push registry.alanhoangnguyen.com/admin/jwt-validator:1.0.10
   ```
4. Update `run_obsidian_remote.yml` to use v1.0.10
5. Restart JWT validator:
   ```bash
   cd /root/Orchestration/obsRemote
   source script/sourceEnv.sh
   docker compose -f run_obsidian_remote.yml up -d jwt_validator
   ```

---

### Task 6: Optional - Enable Dynamic Client Registration (DCR)

**What:** Allow Claude to register itself dynamically without pre-configured credentials

**Benefit:** Better user experience - users don't need to manually configure client ID/secret

**Not required:** Claude supports manual client ID/secret configuration

**If you want to enable DCR:**

1. Login to Keycloak web UI
2. Select realm: `mcp`
3. Navigate: Realm Settings → Client Registration
4. Policies tab → Anonymous Access Policy
5. Set to "Enabled"
6. Configure allowed client registration scopes
7. Save

**Reference:**
- RFC 7591: https://datatracker.ietf.org/doc/html/rfc7591
- Claude docs: https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers

**Verification:**
```bash
# Test DCR endpoint
curl -X POST https://auth.alanhoangnguyen.com/realms/mcp/clients-registrations/default \
  -H "Content-Type: application/json" \
  -d '{
    "clientName": "Test DCR Client",
    "redirectUris": ["https://example.com/callback"]
  }'
```

**Expected:** Client ID and secret returned (if DCR enabled)

---

## Testing & Verification

### Test 1: Verify OAuth Discovery Endpoint

```bash
curl -s https://alanhoangnguyen.com/.well-known/oauth-authorization-server | jq
```

**Checklist:**
- [ ] HTTP 200 OK response
- [ ] Valid JSON returned
- [ ] Contains `issuer` field
- [ ] Contains `authorization_endpoint` field
- [ ] Contains `token_endpoint` field
- [ ] Contains `code_challenge_methods_supported` with "S256"
- [ ] No CORS errors in browser DevTools

### Test 2: Verify Redirect URIs in Keycloak

```bash
# Using kcadm.sh
docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password "$ADMIN_PASSWORD"

docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r mcp \
  --fields clientId,redirectUris | jq '.[] | select(.clientId=="chatgpt-mcp-client")'
```

**Checklist:**
- [ ] `https://claude.ai/api/mcp/auth_callback` present
- [ ] `https://claude.com/api/mcp/auth_callback` present
- [ ] No typos in URLs
- [ ] Both HTTP and HTTPS variants if needed

### Test 3: Verify MCP Endpoint Routing

```bash
# Get OAuth token (or use API key for testing)
TOKEN=$(curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=mcp-tester-1769879674" \
  -d "password=McpTest2026!" \
  | jq -r '.access_token')

# Test initialize
curl -X POST https://alanhoangnguyen.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {"name": "test", "version": "1.0"}
    }
  }' | jq
```

**Checklist:**
- [ ] HTTP 200 OK (not 404, 401, or 502)
- [ ] Valid JSON-RPC response
- [ ] Contains `serverInfo` with name "inventory"
- [ ] No proxy errors in logs

### Test 4: Verify Tools List

```bash
curl -X POST https://alanhoangnguyen.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }' | jq
```

**Checklist:**
- [ ] HTTP 200 OK
- [ ] Response contains `tools` array
- [ ] 7 tools returned
- [ ] Each tool has `name`, `description`, `inputSchema`

**Expected tools:**
1. inventory_get_inventory
2. inventory_get_container
3. inventory_find_location
4. inventory_get_containers
5. inventory_create_items
6. inventory_delete_items
7. inventory

### Test 5: Verify SSE Streaming (GET /mcp)

```bash
curl -N https://alanhoangnguyen.com/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: text/event-stream"
```

**Checklist:**
- [ ] Connection stays open (not immediate close)
- [ ] Events received in SSE format
- [ ] No "broken pipe" errors in JWT validator logs

### Test 6: End-to-End Claude Desktop Test

**Prerequisites:**
- All above tests passed
- Claude Desktop installed on client machine
- Claude Pro/Max/Team/Enterprise account

**Steps:**

1. Open Claude Desktop
2. Settings → Connectors
3. Click "+ Add custom connector"
4. Fill in:
   - **Name:** Inventory Manager (or your choice)
   - **URL:** `https://alanhoangnguyen.com/mcp`
   - Click "Advanced settings"
   - **Client ID:** `chatgpt-mcp-client`
   - **Client Secret:** (from Keycloak client credentials)
5. Click "Connect"

**Expected flow:**
1. ✅ Browser opens to Keycloak login page
2. ✅ Login with `mcp-tester-1769879674` / `McpTest2026!`
3. ✅ Redirect to Claude callback URL
4. ✅ Claude Desktop shows "Connected"
5. ✅ 7 tools appear in Claude's tool list
6. ✅ Can enable/disable tools in UI

**Test tool invocation:**

In Claude Desktop chat:
```
Can you show me my complete inventory?
```

**Expected:**
1. ✅ Claude invokes `inventory_get_inventory` tool
2. ✅ Tool returns inventory data
3. ✅ Claude formats and displays results

**Verify in logs:**
```bash
# Check MCP server received request
./script/see-logs.sh organizerserver | grep -i inventory_get_inventory

# Check JWT validator validated token
docker logs jwt_validator | grep "Token validated successfully"
```

**Checklist:**
- [ ] OAuth flow completes without errors
- [ ] Tools appear in Claude Desktop UI
- [ ] Can invoke tools from chat
- [ ] Tool responses displayed correctly
- [ ] No errors in server logs

---

## Rollback Plan

### If Discovery Endpoint Causes Issues

**Remove nginx location block:**
```bash
cd /root/Orchestration/obsRemote
cp custom_server.conf.backup-<timestamp> custom_server.conf
docker exec nginx_proxy_manager nginx -t
docker exec nginx_proxy_manager nginx -s reload
```

### If Streamable HTTP Routing Causes Issues

**Restore SSE endpoints:**
```bash
cd /root/Orchestration/obsRemote
cp custom_server.conf.backup-<timestamp> custom_server.conf
docker exec nginx_proxy_manager nginx -t
docker exec nginx_proxy_manager nginx -s reload
```

**Revert organizerserver to SSE transport:**
- Local agent must revert code changes
- Redeploy previous version

### If Keycloak Changes Cause Issues

**Revert redirect URIs via Web UI:**
1. Login to Keycloak
2. Remove Claude callback URLs
3. Keep only working URLs

**Or restore from backup if you backed up realm:**
```bash
# If you exported realm before changes
docker exec keycloak /opt/keycloak/bin/kc.sh import --file /tmp/realm-backup.json
```

---

## Success Criteria

- [ ] OAuth discovery endpoint accessible at `/.well-known/oauth-authorization-server`
- [ ] Discovery endpoint returns valid RFC 8414 JSON
- [ ] Claude callback URLs added to Keycloak client
- [ ] No typos in redirect URIs
- [ ] Nginx routes `/mcp` to JWT validator
- [ ] JWT validator validates tokens and proxies to MCP server
- [ ] `/mcp` endpoint returns 200 OK for initialize
- [ ] `/mcp` endpoint returns 7 tools for tools/list
- [ ] SSE streaming works for GET /mcp
- [ ] Claude Desktop can authenticate via OAuth
- [ ] Claude Desktop displays 7 tools
- [ ] Tools can be invoked from Claude Desktop
- [ ] Tool responses work correctly
- [ ] No errors in logs (nginx, jwt-validator, organizerserver)

---

## Dependencies

### Blocked By
- **CRITICAL:** Local agent must complete Streamable HTTP migration first
- organizerserver must be deployed with new transport
- `/mcp` endpoint must be working in container

### Blocks
- End-to-end Claude Desktop integration testing
- Public release of Claude MCP connector

### Related Work
- Local agent transport migration (parallel work)
- Keycloak admin access resolution (prerequisite for Keycloak changes)

---

## References

### OAuth & Discovery
- RFC 8414 (OAuth Server Metadata): https://datatracker.ietf.org/doc/html/rfc8414
- RFC 7591 (Dynamic Client Registration): https://datatracker.ietf.org/doc/html/rfc7591
- Keycloak RFC 8414 discussion: https://github.com/keycloak/keycloak/discussions/40809

### Claude Documentation
- Custom connectors guide: https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers
- Getting started with remote MCP: https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp
- Remote MCP submission: https://support.claude.com/en/articles/12922490-remote-mcp-server-submission-guide

### MCP Specification
- Transports: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- Authorization: https://modelcontextprotocol.io/specification/draft/basic/authorization
- Connect to remote servers: https://modelcontextprotocol.io/docs/develop/connect-remote-servers

### Previous Documentation
- `/root/Orchestration/docs/keycloak-oauth-setup.md` - Initial OAuth setup
- `/root/Orchestration/docs/jwt-validator-sse-fix-2026-01-31.md` - SSE streaming fix
- `/root/Orchestration/docs/mcp-oauth-testing-status-2026-01-31.md` - Testing results
- `/root/Orchestration/docs/oauth-test-results-2026-01-31.md` - PKCE testing
- Local: `docs/ops/keycloak-scope-assignment-problem.md` - Scope assignment attempts
- Local: `docs/ops/organizerserver-host-header-issue.md` - Host validation fix

---

## Alternative: Static Discovery Endpoint

If proxying Keycloak's OIDC discovery doesn't work (missing required RFC 8414 fields), create a static JSON file:

**File:** `/root/Orchestration/obsRemote/oauth-discovery.json`

```json
{
  "issuer": "https://auth.alanhoangnguyen.com/realms/mcp",
  "authorization_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth",
  "token_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token",
  "jwks_uri": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/certs",
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["client_secret_basic", "client_secret_post"],
  "scopes_supported": ["openid", "email", "profile", "offline_access"]
}
```

**Nginx config:**
```nginx
location /.well-known/oauth-authorization-server {
    alias /root/Orchestration/obsRemote/oauth-discovery.json;
    default_type application/json;
    add_header Access-Control-Allow-Origin "*" always;
}
```

**Note:** Must mount the file into nginx container if using this approach.

---

## Notes

### Why OAuth Was Working But Claude Wouldn't Connect

The OAuth chain (Keycloak → JWT validator → MCP server) was actually functioning correctly:
- Tokens were being issued
- JWT validation worked
- Token forwarding succeeded

The problem was **transport layer incompatibility:**
- We built SSE (two endpoints: /sse + /messages/)
- Claude expects Streamable HTTP (single endpoint: /mcp)
- Different protocols, incompatible communication

### Why We Need Both Local and Production Changes

**Local agent:**
- Must change application code (SSE → Streamable HTTP)
- This is a code-level change in organizerserver

**Production agent:**
- Must update infrastructure (OAuth discovery, nginx routing)
- This is configuration-level change in production

**Both are required** - neither can work without the other.

### Custom Scopes Still Unresolved

We couldn't assign `inventory:read` and `inventory:write` scopes due to Keycloak API limitations. Currently using standard OIDC scopes as workaround.

**This is acceptable for MVP** - OAuth authentication works with standard scopes.

**Future improvement:** Solve Keycloak admin access to assign semantic scopes properly.

---

**Last Updated:** 2026-02-03
**Status:** BLOCKED - Waiting for local agent Streamable HTTP migration
**Next Review:** After local agent completes transport changes
**Contact:** Production agent on root@digitalocean
