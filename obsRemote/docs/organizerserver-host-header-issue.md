# MCP Server Host Header Validation Issue

## Summary

The MCP SSE endpoint is rejecting valid OAuth-authenticated requests with "421 Invalid Host header" error, even when DNS rebinding protection is disabled.

## Architecture

```
Client (curl/ChatGPT)
    ↓ HTTPS
nginx (:443)
    ↓ proxy_pass with headers
jwt-validator (:9000)
    ↓ validates JWT, forwards with API key
organizerserver (:3000) - MCP SSE endpoint
```

## Environment Configuration

```bash
MCP_DNS_REBINDING_PROTECTION=false  # Explicitly disabled
MCP_ALLOWED_HOSTS=alanhoangnguyen.com,www.alanhoangnguyen.com
MCP_ALLOWED_ORIGINS=https://alanhoangnguyen.com,https://www.alanhoangnguyen.com
MCP_TRANSPORT=sse
MCP_PORT=3000
```

## What's Working

1. ✅ OAuth token issuance from Keycloak
2. ✅ JWT signature validation in jwt-validator
3. ✅ JWT audience validation (https://alanhoangnguyen.com/mcp)
4. ✅ Request reaches organizerserver (we see the error in logs)

## The Error

**HTTP Response:**
```
HTTP/1.1 421 Misdirected Request
Content-Type: text/plain

Invalid Host header
```

**organizerserver logs:**
```python
File "/usr/local/lib/python3.10/dist-packages/mcp/server/sse.py", line 132, in connect_sse
  raise ValueError("Request validation failed")
ValueError: Request validation failed
```

## Request Details

**Headers being forwarded by jwt-validator:**

```go
// Current implementation in jwt-validator
for key, values := range r.Header {
    if key == "Host" {
        continue // Skip Host, we'll set it explicitly
    }
    for _, value := range values {
        proxyReq.Header.Add(key, value)
    }
}

// Explicitly set Host
if originalHost := r.Header.Get("Host"); originalHost != "" {
    proxyReq.Host = originalHost  // Sets to "alanhoangnguyen.com"
}
```

**What the MCP server receives:**
- `Host: alanhoangnguyen.com` (from client request)
- Backend URL: `http://organizerserver:3000/sse`
- All other headers forwarded correctly

## What We've Tried

1. ✅ Disabled DNS rebinding protection (`MCP_DNS_REBINDING_PROTECTION=false`)
2. ✅ Added Host to allowed hosts list
3. ✅ Explicitly set `proxyReq.Host` to original client Host header
4. ✅ Restarted organizerserver to pick up config changes
5. ❌ Still getting "Request validation failed"

## Suspected Issue

The MCP SSE library (`mcp/server/sse.py` line 132) is performing request validation that goes beyond simple DNS rebinding protection. Possible causes:

1. **HTTP/2 Host mismatch**: The 421 status code is typically used when HTTP/2 receives a request for a hostname it wasn't expecting
2. **Origin validation**: May be checking Origin header or other CORS-related headers
3. **TLS/HTTPS requirement**: May be rejecting non-HTTPS backend connections
4. **Custom validation logic**: Additional checks beyond standard host validation

## Update: Tried Suggested Fixes

We implemented the suggested fix but the issue persists:

```bash
# Current configuration
MCP_DNS_REBINDING_PROTECTION=true
MCP_ALLOWED_HOSTS=alanhoangnguyen.com:*,www.alanhoangnguyen.com:*,alanhoangnguyen.com,localhost:*
MCP_ALLOWED_ORIGINS=https://alanhoangnguyen.com:*,https://www.alanhoangnguyen.com:*

# Verified in container
$ docker exec organizerserver python3 -c "import os; print(os.getenv('MCP_ALLOWED_HOSTS'))"
alanhoangnguyen.com:*,www.alanhoangnguyen.com:*,alanhoangnguyen.com,localhost:*
```

**Still getting:** `421 Invalid Host header`

**Additional tests:**
- ✅ Direct curl to `localhost:3000` with `Host: alanhoangnguyen.com` works (returns "Unauthorized" not "Invalid Host")
- ❌ Through nginx → jwt-validator proxy chain fails with "Invalid Host header"
- ❌ Same error with both HTTP/2 and HTTP/1.1

This suggests the Host header value being validated is different from what we expect. The MCP server is seeing a Host value that doesn't match any pattern in the allowed list, even with wildcards.

## Questions for organizerserver Team

1. What validation does `mcp/server/sse.py:connect_sse` perform besides DNS rebinding?
2. Is there a way to completely disable host validation for proxied requests?
3. Does the MCP server expect the backend URL to match the Host header?
4. Are there any other environment variables we should set?
5. Can we get more detailed error logs from the SSE validation code?

## Test Command

```bash
# Get OAuth token
TOKEN=$(curl -s -X POST \
  "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
  -d "username=mcp-test-user" \
  -d "password=TestPassword123!" \
  | jq -r '.access_token')

# Test MCP endpoint
curl -v https://alanhoangnguyen.com/mcp/sse \
  -H "Authorization: Bearer $TOKEN"

# Result: 421 Invalid Host header
```

## Workaround Needed

We need either:
1. A way to disable all host validation for trusted proxied requests
2. Configuration to tell MCP server to accept `alanhoangnguyen.com` as a valid host even when backend is `organizerserver:3000`
3. Understanding of what the validation is checking so we can pass the right headers

## Additional Context

- organizerserver version: 0.1.3
- Python version: 3.10
- MCP library: Latest from pip
- Deployment: Docker Compose, all services on internal network
- External access: Only through nginx reverse proxy with OAuth

---

**Priority:** High - Blocking OAuth 2.1 implementation for ChatGPT/Claude MCP integration
