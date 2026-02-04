# MCP Server Deployment Guide

How to deploy a new MCP server with OAuth authentication for Claude.ai integration.

---

## Prerequisites

- MCP server application built with **Streamable HTTP transport** (not SSE)
- Docker container for the MCP server
- Access to production server at `/root/Orchestration/obsRemote`

---

## Part 1: MCP Server Application Requirements

### Transport Protocol

Your MCP server **must** use Streamable HTTP transport (MCP spec 2024-11-05 or later).

**Required endpoint:** Single `/mcp` endpoint that handles:
- `POST /mcp` - JSON-RPC requests (initialize, tools/list, tools/call, etc.)
- Returns `text/event-stream` responses with SSE format

**Do NOT use** legacy SSE transport (separate `/sse` and `/messages/` endpoints).

### Required Headers

Your server must:
1. **Return** `mcp-session-id` header on initialize response
2. **Accept** `Mcp-Session-Id` header on subsequent requests
3. **Require** `Accept: application/json, text/event-stream` header

### Response Format

Responses use Server-Sent Events format:
```
event: message
data: {"jsonrpc":"2.0","id":1,"result":{...}}
```

### Example Initialize Response

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache, no-transform
Mcp-Session-Id: abc123def456
Access-Control-Expose-Headers: Mcp-Session-Id

event: message
data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"your-server","version":"1.0.0"}}}
```

### Libraries

Recommended MCP SDK: https://github.com/modelcontextprotocol/python-sdk

```python
# Example using FastMCP (Python)
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("your-server-name")

@mcp.tool()
def your_tool(param: str) -> str:
    """Tool description for Claude."""
    return "result"

# Run with Streamable HTTP transport
mcp.run(transport="streamable-http", host="0.0.0.0", port=3000)
```

---

## Part 2: Infrastructure Configuration

### Step 1: Add Service to Docker Compose

Edit `/root/Orchestration/obsRemote/run_obsidian_remote.yml`:

```yaml
services:
  # ... existing services ...

  your-mcp-server:
    image: registry.alanhoangnguyen.com/admin/your-mcp-server:latest
    container_name: your-mcp-server
    restart: unless-stopped
    networks:
      - obsremote_network
    environment:
      - PORT=3000
      # Add any other env vars your server needs
    # No ports exposed - accessed through nginx/jwt-validator
```

### Step 2: Add Route to JWT Validator

The JWT validator validates OAuth tokens before proxying to your MCP server.

Edit `/root/Orchestration/jwt-validator/main.go` to add your route:

```go
// In the routes section, add:
http.HandleFunc("/your-mcp", func(w http.ResponseWriter, r *http.Request) {
    handleProtectedRoute(w, r, "http://your-mcp-server:3000/mcp")
})
```

Then rebuild and deploy:
```bash
cd /root/Orchestration/jwt-validator
docker build -t registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0 .
docker push registry.alanhoangnguyen.com/admin/jwt-validator:1.2.0

# Update version in run_obsidian_remote.yml
# Then restart:
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d jwt_validator
```

### Step 3: Add Nginx Route

Edit `/root/Orchestration/obsRemote/custom_server.conf`:

```nginx
# Add in the server block for alanhoangnguyen.com (port 443)

# Your MCP Server Endpoint
location /your-mcp {
    proxy_pass http://jwt_validator:9000/your-mcp;

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

Test and reload nginx:
```bash
docker exec nginx_proxy_manager nginx -t
docker exec nginx_proxy_manager nginx -s reload
```

### Step 4: Add Audience to JWT Validator (Optional)

If you want tokens to include your MCP server as an audience, add a protocol mapper in Keycloak:

```bash
# Authenticate to Keycloak
docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin \
  --password 'uDiGhYwhDvgNbp/h2x2V+F2QvEBw/9kLkbtjooBOMrE='

# Get client UUID
CLIENT_UUID=$(docker exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r mcp 2>/dev/null \
  | grep -B 1 '"clientId" : "chatgpt-mcp-client"' | grep '"id"' | sed 's/.*: "\(.*\)".*/\1/')

# Add audience mapper
docker exec keycloak /opt/keycloak/bin/kcadm.sh create clients/$CLIENT_UUID/protocol-mappers/models -r mcp \
  -s name=your-mcp-audience \
  -s protocol=openid-connect \
  -s protocolMapper=oidc-audience-mapper \
  -s 'config."included.custom.audience"=https://alanhoangnguyen.com/your-mcp' \
  -s 'config."access.token.claim"=true'
```

---

## Part 3: Deployment Checklist

### Before Deployment

- [ ] MCP server uses Streamable HTTP transport
- [ ] Server listens on port 3000 (or configured port)
- [ ] Server returns `mcp-session-id` header
- [ ] Server handles session ID in subsequent requests
- [ ] Docker image built and pushed to registry

### Deployment Steps

1. [ ] Add service to `run_obsidian_remote.yml`
2. [ ] Add route to JWT validator
3. [ ] Rebuild and push JWT validator image
4. [ ] Add nginx location block
5. [ ] Test nginx config: `docker exec nginx_proxy_manager nginx -t`
6. [ ] Reload nginx: `docker exec nginx_proxy_manager nginx -s reload`
7. [ ] Start MCP server: `docker compose -f run_obsidian_remote.yml up -d your-mcp-server`
8. [ ] Restart JWT validator: `docker compose -f run_obsidian_remote.yml up -d jwt_validator`

### Verification

```bash
# 1. Get OAuth token
TOKEN=$(curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
  -d "username=mcp-oauth-test" \
  -d "password=McpTest2026" \
  -d "scope=openid" | jq -r '.access_token')

# 2. Test initialize
curl -s -D /tmp/headers.txt -X POST "https://alanhoangnguyen.com/your-mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'

# 3. Check session ID returned
grep -i "mcp-session-id" /tmp/headers.txt

# 4. Test tools/list with session
SESSION_ID=$(grep -i "mcp-session-id:" /tmp/headers.txt | awk '{print $2}' | tr -d '\r\n')
curl -s -X POST "https://alanhoangnguyen.com/your-mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## Part 4: Register with Claude

**URL:** `https://alanhoangnguyen.com/your-mcp`

**OAuth Credentials (shared):**
- Client ID: `chatgpt-mcp-client`
- Client Secret: `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu`

Claude will automatically:
1. Fetch `/.well-known/oauth-authorization-server` for OAuth discovery
2. Redirect user to Keycloak for authentication
3. Exchange authorization code for tokens
4. Call your MCP server with the OAuth token

---

## Existing Infrastructure Reference

| Component | URL/Location |
|-----------|--------------|
| OAuth Discovery | `https://alanhoangnguyen.com/.well-known/oauth-authorization-server` |
| Token Endpoint | `https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token` |
| JWT Validator | `jwt_validator:9000` (internal) |
| Keycloak Admin | Container: `keycloak`, CLI: `/opt/keycloak/bin/kcadm.sh` |
| Nginx Config | `/root/Orchestration/obsRemote/custom_server.conf` |
| Docker Compose | `/root/Orchestration/obsRemote/run_obsidian_remote.yml` |

---

## Troubleshooting

### "Session not found" error
- Ensure you're passing `Mcp-Session-Id` header from initialize response
- Sessions may expire - re-initialize if needed

### "Not Acceptable" error
- Add header: `Accept: application/json, text/event-stream`

### 401 Unauthorized
- Token expired (5 min lifetime) - get fresh token
- Check JWT validator logs: `docker logs jwt_validator`

### 502 Bad Gateway
- MCP server not running or not reachable
- Check container: `docker logs your-mcp-server`
- Verify network: container must be on `obsremote_network`

### Tools not showing in Claude
- Verify tools/list returns tools
- Check server implements MCP 2024-11-05 protocol
- Ensure proper JSON-RPC response format

---

**Last Updated:** 2026-02-03
