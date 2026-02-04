# MCP Transport Migration: SSE → Streamable HTTP
**Local Agent Work - Application Code Changes**

**Date:** 2026-02-03
**Priority:** CRITICAL - Blocks Claude.ai integration
**Owner:** Local Development Agent
**Status:** NOT STARTED

---

## Executive Summary

The MCP server was built using **SSE transport** (legacy), but Claude.ai requires **Streamable HTTP transport** (current standard as of MCP spec 2025-03-26). This requires refactoring the MCP server initialization code in the organizerserver application.

**Impact:** Without this change, Claude Desktop/Web/iOS **cannot** connect to the MCP server, regardless of OAuth configuration.

---

## Feature Description

### What is MCP Transport?

Model Context Protocol (MCP) defines how clients communicate with servers. There are three transport mechanisms:

1. **STDIO** - Local only, process-based communication
2. **SSE** (Legacy) - Two HTTP endpoints: `/sse` (GET) and `/messages/` (POST)
3. **Streamable HTTP** (Current) - Single HTTP endpoint supporting both POST and GET

### Current State

Our MCP server uses **SSE transport**:
- Endpoint 1: `GET /sse` - Client connects, receives session ID
- Endpoint 2: `POST /messages/?session_id=xxx` - Client sends JSON-RPC requests

This architecture was correct when we built it, but MCP deprecated SSE in March 2025.

### Target State

Must migrate to **Streamable HTTP transport**:
- Single endpoint: `/mcp`
- Supports both POST (for requests) and GET (for SSE streaming responses)
- Simpler architecture, better client compatibility

---

## The Problem

### Why Claude Doesn't Work

According to MCP spec and Claude documentation:

1. **Claude Desktop only supports stdio locally** - launches servers as child processes
2. **For remote servers, Claude requires Streamable HTTP transport**
3. **SSE transport is deprecated and not supported by Claude clients**

Sources:
- https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- https://github.com/orgs/modelcontextprotocol/discussions/16
- https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers

### Symptoms Observed

1. **ChatGPT Integration:**
   - OAuth authentication succeeds
   - SSE connection establishes but closes within 1 second
   - "Zero tools" returned - connection incompatible
   - Error: "broken pipe" in JWT validator logs

2. **Claude.ai Integration:**
   - Not yet tested, but will fail for same reason
   - Claude expects `/mcp` endpoint, we provide `/mcp/sse` + `/mcp/messages/`

### Root Cause Analysis

The MCP server was implemented correctly for the SSE spec that existed at the time. However:
- MCP spec updated to version 2025-03-26 on March 26, 2025
- SSE transport marked as legacy/deprecated
- New standard is Streamable HTTP
- All modern MCP clients (Claude, ChatGPT) expect Streamable HTTP

**Timeline:**
- We built SSE transport (correct for old spec)
- MCP deprecated SSE in favor of Streamable HTTP
- Claude clients don't support SSE for remote servers
- Our server is incompatible with current client expectations

---

## What We Tried (OAuth Debugging)

Before discovering the transport incompatibility, we attempted to fix OAuth issues:

### Attempt 1: JWT Validator SSE Streaming Fix
- **What:** Fixed JWT validator to flush SSE responses immediately
- **Version:** jwt-validator v1.0.9
- **Result:** Partially helped, but didn't solve core issue
- **Why:** Transport layer incompatibility, not just buffering

### Attempt 2: Keycloak Scope Configuration
- **What:** Tried to assign custom scopes (inventory:read, inventory:write)
- **Methods:** kcadm.sh, REST API, direct client updates
- **Result:** All methods failed due to Keycloak API limitations
- **Workaround:** Using standard OIDC scopes (openid, email, profile)
- **Why it didn't matter:** Transport layer was broken anyway

### Attempt 3: Host Header Validation
- **What:** Configured MCP_ALLOWED_HOSTS to prevent 421 errors
- **Result:** Resolved host validation errors
- **Why it didn't solve the problem:** Transport incompatibility remained

### Attempt 4: OAuth Token Exchange Testing
- **What:** Tested PKCE flow end-to-end with Keycloak
- **Result:** Authorization codes generated, but token exchange failed
- **Status:** Still unresolved, but blocked by transport issue anyway

### Key Discovery (2026-02-03)

After extensive OAuth debugging, we found the root cause via web research:
- SSE transport is deprecated in MCP spec
- Claude requires Streamable HTTP for remote servers
- Our entire SSE architecture is incompatible with current MCP clients

**This invalidated all previous debugging efforts** - the OAuth chain works, but the transport layer doesn't.

---

## The Fix

### Overview

Refactor the MCP server initialization to use Streamable HTTP transport instead of SSE transport.

### Implementation Plan

#### Step 1: Locate MCP Server Initialization Code

**Expected location:**
```
src/main/java/com/nguyen/server/
```

**What to find:**
- Python MCP server initialization (likely using FastMCP library)
- Current code probably looks like:
  ```python
  from mcp.server.fastmcp import FastMCP

  mcp = FastMCP("inventory")

  # ... tool definitions ...

  if __name__ == "__main__":
      mcp.run(transport="sse")  # ← THIS IS THE PROBLEM
  ```

**Files to check:**
- Search for `mcp.run(` in Python files
- Search for `FastMCP` imports
- Check how the MCP server process is started in the Java application

#### Step 2: Update to Streamable HTTP Transport

**Old code:**
```python
mcp.run(transport="sse")
```

**New code:**
```python
mcp.run(transport="streamable-http")
```

**Expected changes:**
- Server will expose single endpoint instead of two
- Endpoint path should be `/mcp` (not `/sse` or `/messages/`)
- FastMCP library should handle all protocol details automatically

#### Step 3: Verify MCP Library Version

**Check current version:**
```bash
# In organizerserver container or requirements.txt
pip show mcp-server-python
```

**Required version:**
- Must support Streamable HTTP transport (MCP spec 2025-03-26 or later)
- If version is too old, update `requirements.txt` or equivalent

**Update if needed:**
```python
# requirements.txt
mcp-server-python>=1.0.0  # Verify correct version number for Streamable HTTP support
```

#### Step 4: Update Environment Configuration

**File:** `config.yml` or environment variables

**Current config:**
```yaml
MCP_TRANSPORT=sse
MCP_PORT=3000
```

**New config:**
```yaml
MCP_TRANSPORT=streamable-http  # Updated transport
MCP_PORT=3000  # Keep same port
```

**Environment variables to verify:**
- `MCP_TRANSPORT` - Must be "streamable-http"
- `MCP_PORT` - Default 3000 is fine
- `MCP_API_KEY` - Keep for backward compatibility
- `MCP_OAUTH_*` - Keep all OAuth settings

#### Step 5: Update Application Startup

**If Java application starts MCP server as subprocess:**

Check how the Python MCP server is invoked. Ensure no hardcoded paths like `/sse` or `/messages/` in the startup command.

**Expected startup command:**
```bash
python3 /path/to/mcp_server/server.py --transport streamable-http --port 3000
```

---

## Testing & Verification

### Local Testing (Pre-deployment)

#### Test 1: Verify Server Starts with Streamable HTTP

```bash
# Build the application
./build/build.sh

# Run locally
# Check logs for MCP server startup message
```

**Expected log output:**
```
Starting MCP Inventory Server
Transport: streamable-http
Port: 3000
Endpoint: /mcp
```

**Verify:**
- ✅ No errors during startup
- ✅ Log shows "streamable-http" transport
- ✅ Single endpoint `/mcp` mentioned (not `/sse` and `/messages/`)

#### Test 2: Test Endpoint Responds

```bash
# Test the /mcp endpoint directly (without OAuth for now)
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }'
```

**Expected response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {...},
    "serverInfo": {
      "name": "inventory",
      "version": "1.26.0"
    }
  }
}
```

**Verify:**
- ✅ HTTP 200 OK response
- ✅ Valid JSON-RPC response
- ✅ Server info includes name and version

#### Test 3: Test tools/list Method

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }'
```

**Expected response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "inventory_get_inventory",
        "description": "Get complete inventory...",
        "inputSchema": {...}
      },
      // ... 6 more tools
    ]
  }
}
```

**Verify:**
- ✅ HTTP 200 OK response
- ✅ Returns array of 7 tools
- ✅ Each tool has name, description, inputSchema

#### Test 4: Test GET for SSE Streaming (Streamable HTTP supports both)

```bash
curl -N http://localhost:3000/mcp \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -H "Accept: text/event-stream"
```

**Expected response:**
```
event: message
data: {"jsonrpc":"2.0", ...}
```

**Verify:**
- ✅ Connection stays open (SSE stream)
- ✅ Events received in SSE format
- ✅ Connection doesn't close immediately

---

### Deployment Testing (Post-production deploy)

**After production agent completes their work** (OAuth config, nginx routing, etc.):

#### Test 1: Verify Endpoint Through Proxy Chain

```bash
# From production host
curl -X POST https://alanhoangnguyen.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OAUTH_TOKEN" \
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
- ✅ HTTP 200 OK through entire chain (nginx → jwt-validator → mcp-server)
- ✅ Valid JSON-RPC response
- ✅ No proxy errors in logs

#### Test 2: OAuth Discovery Works

```bash
curl https://alanhoangnguyen.com/.well-known/oauth-authorization-server
```

**Expected:**
```json
{
  "issuer": "https://auth.alanhoangnguyen.com/realms/mcp",
  "authorization_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth",
  "token_endpoint": "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token",
  "code_challenge_methods_supported": ["S256"],
  ...
}
```

**Verify:**
- ✅ Discovery endpoint returns valid JSON
- ✅ All required OAuth endpoints listed
- ✅ S256 PKCE supported

#### Test 3: Claude Desktop Connection (End-to-end)

**In Claude Desktop:**
1. Settings → Connectors → Add custom connector
2. URL: `https://alanhoangnguyen.com/mcp`
3. Client ID: (from Keycloak client)
4. Client Secret: (from Keycloak client)
5. Click "Connect"

**Expected flow:**
1. Claude fetches discovery endpoint
2. Claude redirects to Keycloak authorization page
3. User logs in to Keycloak
4. Claude receives OAuth token
5. Claude sends `initialize` request to `/mcp`
6. Claude sends `tools/list` request
7. Claude displays 7 inventory tools

**Verify:**
- ✅ OAuth flow completes without errors
- ✅ Tools appear in Claude Desktop UI
- ✅ Can invoke tools successfully
- ✅ Tool responses work correctly

---

## Rollback Plan

If Streamable HTTP causes issues:

### Rollback Code Changes

```bash
# Revert to previous version
git revert <commit-hash>

# Rebuild and redeploy
./build/build.sh
# ... deploy to production
```

### Rollback Environment Config

```yaml
# Restore in config.yml
MCP_TRANSPORT=sse
```

### Rollback Production Nginx

Production agent must restore old nginx config with `/mcp/sse` and `/mcp/messages/` endpoints.

---

## Success Criteria

- [ ] MCP server starts with Streamable HTTP transport
- [ ] Single `/mcp` endpoint responds to POST requests
- [ ] `initialize` method works locally
- [ ] `tools/list` returns 7 tools locally
- [ ] Endpoint works through nginx → jwt-validator → mcp-server chain
- [ ] OAuth discovery endpoint accessible
- [ ] Claude Desktop can authenticate via OAuth
- [ ] Claude Desktop displays 7 inventory tools
- [ ] Tools can be invoked from Claude Desktop
- [ ] Tool responses work correctly

---

## Dependencies

### Blocked By
Nothing - can proceed immediately

### Blocks
- Production agent OAuth configuration work
- Production agent nginx routing updates
- End-to-end Claude integration testing

---

## References

### MCP Specification
- Transport spec: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- Why SSE deprecated: https://blog.fka.dev/blog/2025-06-06-why-mcp-deprecated-sse-and-go-with-streamable-http/
- MCP transport comparison: https://mcpcat.io/guides/comparing-stdio-sse-streamablehttp/

### Claude Documentation
- Custom connectors: https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers
- Remote server guide: https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp

### Previous Work
- `docs/ops/keycloak-oauth-setup.md` - OAuth setup documentation
- `docs/ops/organizerserver-host-header-issue.md` - Host validation fixes
- `docs/task-log/mcp-oauth-testing-status-2026-01-31.md` - OAuth testing results

---

## Notes

### Why We Built SSE Initially

SSE transport was the correct choice when we started:
- It was the standard for remote MCP servers
- Well documented and supported
- Worked with the MCP Python SDK we used

### Why We Must Change Now

The MCP ecosystem evolved:
- Spec updated to 2025-03-26 version
- Streamable HTTP became the new standard
- Claude clients don't support SSE for remote servers
- All modern MCP documentation recommends Streamable HTTP

### Migration Is Required

This is not optional - without this change, Claude integration **cannot work**.

---

**Last Updated:** 2026-02-03
**Next Review:** After implementation and testing
**Contact:** Local development agent
