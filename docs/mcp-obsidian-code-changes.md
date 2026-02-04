# MCP Obsidian Code Changes Summary

**Date:** 2026-02-03
**Version:** 1.0.1
**Commit:** c529a66

---

## Summary

Migrated mcp-obsidian from legacy SSE transport to Streamable HTTP transport for production deployment with OAuth authentication.

---

## Changes Made

### src/index.js

**Before:**
- Used `SSEServerTransport` from SDK
- Two endpoints: `GET /sse` and `POST /message?sessionId=XXX`
- Session ID via query parameter
- No express.json() middleware

**After:**
- Uses `StreamableHTTPServerTransport` from SDK
- Single endpoint: `POST /mcp`
- Session ID via `Mcp-Session-Id` header
- Added `express.json()` middleware for body parsing
- Added `Mcp-Session-Id` to CORS allowed/exposed headers

**Key Implementation Details:**
```javascript
// Session management via headers
const sessionIdHeader = req.headers['mcp-session-id'];

// Initialize creates new session
const transport = new StreamableHTTPServerTransport({
  sessionIdGenerator: () => sessionId,
  onsessioninitialized: (sid) => { ... },
  onsessionclosed: (sid) => { ... }
});

// Handle request
await transport.handleRequest(req, res, req.body);
```

---

## Protocol Compliance

### MCP Protocol Version
- **Previous:** 2024-09-01 (SSE)
- **Current:** 2024-11-05 (Streamable HTTP)

### Transport Specification
- Single `/mcp` endpoint for all requests
- Session ID returned in `mcp-session-id` response header
- Session ID provided in `Mcp-Session-Id` request header
- SSE format responses (`event: message\ndata: {...}`)
- Proper CORS headers for cross-origin requests

---

## Testing

### Unit Tests
- All 340 existing tests pass
- No breaking changes to tool implementations

### Integration Tests
Created `scripts/test-streamable-http.sh`:
- Health check endpoint
- Initialize with session ID header
- tools/list with session header
- tools/call with session header
- Error handling (missing/invalid session)

---

## Docker Image

**Registry:** `registry.alanhoangnguyen.com/admin/mcp-obsidian`

**Tags:**
- `latest` - Always newest build
- `1.0.1` - Semantic version (from VERSION file)
- `c529a66` - Git commit hash
- `20260204...` - Build timestamp

**Build Command:**
```bash
./scripts/ci/build-and-push.sh patch
```

---

## Deployment Status

**Image:** Built and pushed to registry
**Compose:** Configuration documented (not yet applied)
**JWT Route:** Configuration documented (not yet applied)
**Nginx:** Configuration documented (not yet applied)

---

## Next Steps

1. Add mcp-obsidian service to `run_obsidian_remote.yml`
2. Add `/obsidian-mcp` route to JWT validator
3. Rebuild and push JWT validator
4. Add nginx location block
5. Deploy mcp-obsidian container
6. Test with OAuth token
7. Register with Claude.ai

---

## Files Changed

| File | Change |
|------|--------|
| `src/index.js` | Migrated SSE → Streamable HTTP |
| `scripts/test-streamable-http.sh` | New test script |
| `VERSION` | 1.0.0 → 1.0.1 |

---

## Backward Compatibility

**Breaking Change:** The transport protocol has changed from SSE to Streamable HTTP.

**Impact:**
- Old clients using `/sse` + `/message` will not work
- New clients must use `/mcp` endpoint with header-based sessions
- mcp-proxy or Claude Desktop with HTTP transport required

---

## Security Considerations

- OAuth token validation via JWT validator
- Session-based authentication after initialization
- No sensitive data in URL parameters
- CORS configured for cross-origin requests
