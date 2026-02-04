# MCP Tools List Investigation - ChatGPT Shows Zero Tools

**Date:** 2026-01-31
**Status:** Critical - ChatGPT Cannot See MCP Tools

---

## Problem Summary

ChatGPT successfully connects to the MCP server via OAuth, but shows:
> "All tools are hidden. Make at least one tool public to use it in ChatGPT."

**However, there is NO tool list displayed to enable.** This indicates the MCP server is not returning tools via the `tools/list` method.

---

## What We Know

### ✅ Working
- OAuth authentication (token exchange works)
- SSE connection established
- JWT validator streaming fix deployed
- ChatGPT receives the SSE endpoint event
- HTTP 202 responses from `/mcp/messages/`

### ❌ Not Working
- `tools/list` method returns empty/no tools to ChatGPT
- ChatGPT shows "All tools are hidden" but no tools are listed

---

## MCP Protocol Flow

Expected flow:
```
1. ChatGPT → SSE: GET /mcp/sse
   ← event: endpoint
   ← data: /messages/?session_id=xxx

2. ChatGPT → POST /mcp/messages/?session_id=xxx
   {
     "jsonrpc": "2.0",
     "id": 1,
     "method": "initialize",
     "params": {...}
   }

3. ChatGPT → POST /mcp/messages/?session_id=xxx
   {
     "jsonrpc": "2.0",
     "id": 2,
     "method": "tools/list"
   }
   ← Should return: {tools: [...]} ← THIS IS FAILING
```

---

## Investigation Steps for Production Agent

### Step 1: Check MCP Server Logs

```bash
# Get MCP server logs
docker logs obsremote-organizerserver-1 --tail 100 2>&1 | grep -i -E 'mcp|tool|jsonrpc|method'

# Look for:
# - tools/list method being called
# - Any errors processing the request
# - Tools being registered at startup
```

### Step 2: Test Tools/List Directly

```bash
# Get a valid OAuth token first (use existing test token or generate new)
ACCESS_TOKEN="<valid_oauth_token>"

# 1. Start SSE session
curl -N https://alanhoangnguyen.com/mcp/sse \
  -H "Authorization: Bearer $ACCESS_TOKEN" 2>&1 &

# 2. Extract session_id from "event: endpoint" response

# 3. Send initialize request
curl -X POST "https://alanhoangnguyen.com/mcp/messages/?session_id=<SESSION_ID>" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
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

# 4. Send tools/list request
curl -X POST "https://alanhoangnguyen.com/mcp/messages/?session_id=<SESSION_ID>" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list"
  }'

# Expected: JSON response with tools array
# Actual: ??? (need to verify)
```

### Step 3: Check MCP Server Implementation

Look at how the MCP server handles `tools/list`:

```bash
# Find the server code
docker exec obsremote-organizerserver-1 find /app -name "*.py" -path "*mcp*" 2>/dev/null

# Check if tools are registered
docker exec obsremote-organizerserver-1 grep -r "tools/list" /app/ 2>/dev/null
docker exec obsremote-organizerserver-1 grep -r "@mcp.tool" /app/ 2>/dev/null
```

### Step 4: Verify FastMCP Setup

The MCP server uses FastMCP. Check:

1. **Is the server using FastMCP correctly?**
   ```python
   from mcp.server.fastmcp import FastMCP
   mcp = FastMCP("inventory")

   @mcp.tool()
   async def inventory_get_inventory() -> str:
       ...
   ```

2. **Are tools registered at startup?**
   - FastMCP should auto-discover @mcp.tool decorated functions
   - Check if tools module is being imported

3. **Is SSE transport properly configured?**
   ```python
   mcp.run(transport="sse")  # or mcp.sse_app()
   ```

### Step 5: Check JWT Validator Passing Requests

Verify the JWT validator is correctly forwarding POST requests:

```bash
# Check JWT validator logs for POST /messages/
docker logs jwt_validator --tail 50 | grep -i "POST\|tools"

# Verify it's not filtering or modifying the request body
```

---

## Questions to Answer

1. **Does the MCP server receive the `tools/list` request?**
   - Check logs for incoming JSON-RPC requests

2. **Does the server process the request?**
   - Look for any errors or exceptions

3. **What does the server return?**
   - Empty tools array? Error response? No response?

4. **Are tools registered at server startup?**
   - Check if @mcp.tool decorated functions are discovered

5. **Is the response being blocked/filtered?**
   - JWT validator logs
   - Nginx logs

---

## Test Token for Debugging

Use this valid OAuth token (get a fresh one if expired):
```
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoSEhYeS1WLUJoazRPRGQyN2RiZjliOUJuNW0ycVNHZzFzZlBLanJoLVhnIn0...
```

Or generate a new one using the PKCE flow documented in previous sessions.

---

## Expected Tools

Based on the MCP server code, these tools should be available:

1. `inventory_get_inventory` - Get all inventory
2. `inventory_get_container` - Get specific container contents
3. `inventory_find_location` - Find item location
4. `inventory_get_containers` - List all containers
5. `inventory_create_items` - Add items to container
6. `inventory_delete_items` - Remove items from container
7. `inventory` - Natural language meta-tool

---

## Files to Check

```
# MCP Server code
/root/Orchestration/obsRemote/dev/docker-compose.env
/app/mcp_server/mcp_inventory/server.py
/app/mcp_server/mcp_inventory/tools/*.py

# Logs
docker logs obsremote-organizerserver-1
docker logs jwt_validator
/var/log/nginx/error.log
```

---

## Success Criteria

- [ ] `tools/list` request returns array of 7 tools
- [ ] ChatGPT displays tools in the Actions section
- [ ] Tools can be enabled/disabled in ChatGPT UI
- [ ] ChatGPT can invoke tools successfully

---

**Priority:** Critical - Blocks all MCP functionality
**Assigned:** Production Agent
**Created:** 2026-01-31
