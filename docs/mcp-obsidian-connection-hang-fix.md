# MCP Obsidian Connection Hang Fix

**Date:** 2026-02-04
**Issue:** HTTP connections staying open after response, causing client hangs
**Fix Commit:** 96cb1ad

---

## Problem

mcp-obsidian server kept HTTP connections open after sending responses, causing clients to hang/timeout indefinitely.

### Symptoms
- `curl` to `/mcp` endpoint would hang after receiving response
- organizerserver (same Streamable HTTP transport) worked correctly
- Server logs showed requests being processed but connections not closing

### Root Cause

**Architecture mismatch:** A single MCP server instance was being reused across multiple transport instances.

```javascript
// BROKEN CODE (before fix)
const mcpServer = createServer(vaultPath);  // Single server
let serverConnected = false;

// For each session:
const transport = new StreamableHTTPServerTransport({...});
if (!serverConnected) {
  await mcpServer.connect(transport);  // Connected to FIRST transport only!
  serverConnected = true;
}
// Subsequent sessions: server still connected to first transport
```

**Why it failed:**
1. First initialize: Create transport A, connect server to A ✓
2. Response to first request: Server sends to transport A ✓
3. Second request (session B): Retrieve transport B, call handleRequest
4. Server receives request, processes it, sends response... to transport A!
5. Transport B's stream never receives response → connection hangs

The MCP Server class stores the transport in `this._transport` and uses it for ALL responses. It can only be connected to ONE transport at a time.

---

## Solution

Create a separate MCP server for EACH session:

```javascript
// FIXED CODE (after fix)
const sessions = new Map();

// For each initialize request:
const mcpServer = createServer(vaultPath);  // New server per session
const transport = new StreamableHTTPServerTransport({...});
await mcpServer.connect(transport);  // Each server connected to its own transport
sessions.set(sessionId, { transport, server: mcpServer });

// For subsequent requests:
const { transport } = sessions.get(sessionId);
await transport.handleRequest(req, res, req.body);
// Server sends response to its own transport ✓
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/index.js` | Create server per session instead of reusing single server |

---

## Verification

Local test passes:
```bash
# Initialize - returns immediately with session ID
curl -s -D /tmp/h.txt -X POST http://localhost:3000/mcp \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize",...}'

# tools/list with session - returns immediately, no hang
curl -s -X POST http://localhost:3000/mcp \
  -H "Mcp-Session-Id: <session-id>" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## Deployment

1. Build new image with fix:
   ```bash
   ./scripts/ci/build-and-push.sh patch  # 1.0.1 → 1.0.2
   ```

2. Deploy to production:
   ```bash
   ./scripts/ci/deploy_container.sh 1.0.2
   ```

3. Test production endpoint:
   ```bash
   TOKEN=$(curl -s -X POST "https://auth.alanhoangnguyen.com/..." | jq -r '.access_token')

   # Should return immediately, no hang
   curl -s -D /tmp/h.txt -X POST "https://alanhoangnguyen.com/obsidian-mcp" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Accept: application/json, text/event-stream" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize",...}'
   ```

---

## Lesson Learned

**MCP Server instances are NOT thread-safe across transports.** Each server can only be connected to one transport at a time. For multi-session support, either:

1. Create a server per session (what we did) - simple, scales with sessions
2. Implement a routing layer that manages the server-transport mapping
3. Use a single transport that handles all sessions internally

Option 1 is the simplest and matches the SDK's design intent.
