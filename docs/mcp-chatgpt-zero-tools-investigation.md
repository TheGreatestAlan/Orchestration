# MCP ChatGPT Integration Issue - Zero Tools Returned

**Date:** 2026-01-31
**Reporter:** Local Development Agent
**Severity:** High - Blocks ChatGPT integration

---

## Problem Statement

ChatGPT successfully connects to the MCP server but receives zero tools, making the integration unusable.

**ChatGPT shows:**
- ✅ Connected to: `https://alanhoangnguyen.com/mcp/sse`
- ✅ OAuth authentication working
- ❌ "All tools are hidden. Make at least one tool public to use it in ChatGPT."
- ❌ No tools list visible in the connector editor UI

**Root cause:** MCP server is not returning any tools in response to ChatGPT's tools/list request.

---

## Evidence

### 1. Connection Successful
```
Server logs (obsremote-organizerserver-1):
INFO:     172.18.0.16:53442 - "GET /sse HTTP/1.1" 200 OK
INFO:     172.18.0.16:38302 - "GET /sse HTTP/1.1" 200 OK
```

These requests (around 17:33 UTC) were ChatGPT connecting with valid OAuth tokens.

### 2. OAuth Working
```bash
$ curl https://alanhoangnguyen.com/mcp/sse
{"error":"missing_authorization","error_description":"Authorization header is required"}
```

Server correctly enforces OAuth authentication.

### 3. ChatGPT Configuration
- App name: `myInventory`
- Auth type: OAuth (working)
- Endpoint: `/mcp/sse`
- Expected: List of tools from inventory, notes, todos
- Actual: Zero tools returned

---

## Investigation Needed (Production Agent)

### 1. MCP Protocol Implementation
**Question:** How is the `/mcp/sse` endpoint implemented?

**Check:**
- Is this a proper MCP SSE transport implementation?
- Does it implement the MCP protocol `tools/list` method?
- Is it using the official MCP SDK or custom implementation?

**Files to check:**
- Where is `/mcp/sse` endpoint defined? (not found in Java resources)
- `custom_server.conf` - routing configuration
- Any MCP-specific service/handler code

### 2. Tool Registration
**Question:** Are tools properly registered with the MCP server?

**Expected tools from existing API endpoints:**
```
/inventory/item/{itemName}          → search_inventory tool
/inventory/items                    → list_inventory_items tool
/note/*                            → note management tools
/todo/*                            → todo management tools
```

**Check:**
- Are these REST endpoints wrapped as MCP tools?
- Is there an MCP tool registry/catalog?
- Are tools being registered at startup?

### 3. MCP Response Format
**Question:** What does the server return when ChatGPT requests tools?

**Action:** Enable debug/trace logging for the `/mcp/sse` endpoint and reproduce a ChatGPT connection attempt.

**Look for:**
- Incoming MCP requests (tools/list, initialize, etc.)
- Outgoing MCP responses (empty tools array? error?)
- Any exceptions/errors during MCP handshake

### 4. SSE Transport Specifics
**Question:** Is the SSE transport properly streaming MCP responses?

**MCP over SSE requires:**
- Proper SSE event stream format
- JSON-RPC 2.0 messages
- `tools/list` method handler

**Check:**
- Is the SSE connection staying open?
- Are events being sent in correct SSE format?
- Is tools/list method implemented?

---

## Diagnostic Commands

Run these on production server and report findings:

```bash
# 1. Check nginx/proxy routing to /mcp/sse
cat /root/Orchestration/obsRemote/custom_server.conf | grep -A 15 '/mcp'

# 2. Check if there's MCP-specific code
find /root/Orchestration/obsRemote -name "*.java" -o -name "*.py" | xargs grep -l "MCP\|tools.*list"

# 3. Enable debug logging (if not already)
# - Check application.yml or logback.xml for logging config
# - Set MCP-related packages to DEBUG level

# 4. Test MCP handshake manually
# - Connect to /mcp/sse with curl and send MCP initialize request
# - Check if server responds with proper MCP protocol

# 5. Check for MCP SDK dependencies
grep -i "mcp" /root/Orchestration/obsRemote/pom.xml
grep -i "mcp" /root/Orchestration/obsRemote/build.gradle
grep -i "mcp" /root/Orchestration/obsRemote/requirements.txt
```

---

## Expected Outcome

MCP server should return tools in this format:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "search_inventory",
        "description": "Search for items in inventory",
        "inputSchema": {
          "type": "object",
          "properties": {
            "query": {"type": "string", "description": "Search query"}
          },
          "required": ["query"]
        }
      },
      {
        "name": "list_inventory",
        "description": "List all inventory items",
        "inputSchema": {
          "type": "object",
          "properties": {}
        }
      }
    ]
  }
}
```

---

## Quick Win Possibility

If the MCP server isn't implemented yet (just the endpoint exists), the fastest path is:

1. Add MCP SDK dependency
2. Wrap existing REST endpoints as MCP tools
3. Implement tools/list handler
4. Test with ChatGPT

---

## Request to Production Agent

Please investigate:

1. **How is `/mcp/sse` currently implemented?** (share relevant code/config)
2. **Is MCP protocol implemented or just the endpoint?**
3. **Enable debug logging and capture a ChatGPT connection attempt** (share logs)
4. **List what tools SHOULD be exposed** (based on existing APIs)
5. **Recommend implementation approach** if MCP protocol not yet implemented

Report findings to: `/root/Orchestration/docs/mcp-investigation-results-2026-01-31.md`

---

## Related Issues

- OAuth token exchange failing (separate issue, documented in oauth-test-results)
- This blocks ChatGPT integration even though OAuth connection works

---

**Priority:** High - ChatGPT is successfully authenticating but cannot use the service

**Next Action:** Production agent investigates MCP implementation and reports findings
