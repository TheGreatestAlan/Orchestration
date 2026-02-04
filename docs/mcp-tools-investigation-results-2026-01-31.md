# MCP Tools Investigation Results

**Date:** 2026-01-31
**Status:** MCP Server Working - SSE Connection Issue Identified

---

## Key Finding

**The MCP server correctly returns 7 tools when tested locally.** The issue is with SSE connection persistence through the proxy chain.

### Verified Working (Local Test)

```
[SSE] Session ID: 6e07959f75984d73a8a2a430e9ffda55
[POST] Sending initialize - Response: 202 Accepted
[SSE] Received: {"jsonrpc":"2.0","id":1,"result":{...serverInfo":{"name":"inventory","version":"1.26.0"}}}
[POST] Sending tools/list - Response: 202 Accepted
[SSE] Received: {"jsonrpc":"2.0","id":2,"result":{"tools":[7 tools...]}}
```

### Tools Available

1. `inventory_get_inventory` - Get all inventory
2. `inventory_get_container` - Get container contents
3. `inventory_find_location` - Find item location
4. `inventory_get_containers` - List containers
5. `inventory_create_items` - Add items
6. `inventory_delete_items` - Remove items
7. `inventory` - Natural language interface

---

## Issue Identified: SSE Connection Closes Prematurely

### Symptom

From JWT validator logs:
```
18:24:43 INFO: Token validated successfully
18:24:44 WARN: Error writing SSE response: broken pipe
```

The SSE connection closes within 1 second of opening.

### Root Cause Analysis

The MCP SSE protocol requires:
1. Client opens GET /sse → receives `event: endpoint` with session_id
2. **SSE connection stays open** for receiving responses
3. Client sends POST /messages/ → gets 202 Accepted
4. Response delivered via SSE stream from step 1

The `ClosedResourceError` in MCP server logs indicates:
- POST request is received (202 Accepted)
- Server tries to send response via SSE
- **But the SSE stream is already closed**

### Possible Causes

1. **Client (ChatGPT) reconnection behavior** - May open/close SSE rapidly
2. **Nginx proxy timeout** - Check `proxy_send_timeout`
3. **JWT validator streaming issue** - SSE flush may not be working correctly

---

## Current Configuration Status

### Nginx (`/mcp/sse`)
```nginx
proxy_buffering off;    ✓
proxy_cache off;        ✓
proxy_read_timeout 3600s; ✓
Connection "";          ✓ (required for SSE)
```

### JWT Validator (v1.0.9)
- SSE detection: ✓
- Flushing after writes: ✓
- Long timeout: ✓ (3600s)

### MCP Server
- Tools registered: ✓ (7 tools)
- SSE transport: ✓
- Local test passes: ✓

---

## Recommended Next Steps

### 1. Test with Fresh OAuth Token

The local testing agent should:
```bash
# Get fresh token with openid scope
# Test SSE connection persistence
curl -N https://alanhoangnguyen.com/mcp/sse \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Accept: text/event-stream"
```

Observe if events are received and connection stays open.

### 2. Check if Issue is ChatGPT-Specific

Test with a simple MCP client that:
- Opens SSE connection
- Waits for endpoint event
- Sends initialize
- Waits for response via SSE
- Sends tools/list
- Waits for response via SSE

If this works, the issue is ChatGPT's MCP client implementation.

### 3. Add nginx send_timeout

May help with connection persistence:
```nginx
location /mcp/sse {
    proxy_send_timeout 3600s;  # Add this
    ...
}
```

### 4. Check Keycloak Scope Issue

Some tokens missing `openid` scope:
```
WARN: insufficient scopes: got [email profile], required [openid email profile]
```

Ensure Keycloak client always includes `openid` scope.

---

## Test Script (for reference)

The following Python script verified MCP works locally:

```python
# Run inside organizerserver container
docker exec obsremote-organizerserver-1 python3 /tmp/mcp_test.py
```

Output shows 7 tools returned correctly via SSE.

---

## Files Involved

| File | Purpose |
|------|---------|
| `/root/Orchestration/jwt-validator/main.go` | SSE streaming proxy (v1.0.9) |
| `/root/Orchestration/obsRemote/custom_server.conf` | Nginx proxy config |
| `/usr/local/lib/mcp_server/mcp_inventory/server.py` | MCP server (in container) |

---

**Conclusion:** MCP server is working correctly. The issue is SSE connection persistence when accessed through OAuth + proxy chain. Recommend testing with a controlled MCP client to isolate whether the issue is ChatGPT-specific.
