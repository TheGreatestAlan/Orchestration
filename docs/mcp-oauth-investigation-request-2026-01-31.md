# MCP OAuth Integration Investigation Request

**Date:** 2026-01-31
**From:** Local Testing Agent
**To:** Production Agent (root@digitalocean)
**Priority:** High - Blocking ChatGPT MCP Integration

---

## Background

I've successfully completed OAuth 2.1 PKCE token acquisition from Keycloak:
- Keycloak realm `mcp` is working
- Authorization code flow completes successfully
- JWT access tokens are being issued with correct scopes (`openid email profile`)
- Token audience includes `https://alanhoangnguyen.com/mcp`

However, when connecting to `https://alanhoangnguyen.com/mcp/sse` with the OAuth token, the SSE connection establishes but **no events are received**. This suggests either:
1. Nginx is rejecting OAuth tokens (expecting API key only)
2. MCP server doesn't have OAuth enabled
3. OAuth shim is not running or misconfigured
4. SSE endpoint paths are different than expected

---

## Investigation Tasks

### Task 1: Verify MCP Deployment Configuration

**Check the organizer server container environment:**
```bash
docker exec obsremote-organizerserver-1 env | grep -E 'MCP|OAUTH|INVENTORY' | sort
```

**Specifically verify:**
- Is `MCP_TRANSPORT=sse` set?
- Is `MCP_OAUTH_ENABLED=true` set?
- What is `MCP_OAUTH_ISSUER` set to?
- What is `MCP_OAUTH_AUDIENCE` set to?
- Is `MCP_API_KEY` set? (may conflict with OAuth)
- What is `INVENTORY_API_BASE_URL`?
- Is `MCP_PORT=3000`?

### Task 2: Check MCP Server Logs

**Get recent MCP server logs:**
```bash
docker logs obsremote-organizerserver-1 --tail 100 2>&1 | grep -i -E 'mcp|oauth|sse|error|warn'
```

**Look for:**
- MCP server startup messages
- OAuth validation errors
- SSE connection attempts
- Any errors about JWT validation

### Task 3: Verify OAuth Shim Status

**Check if OAuth shim container exists:**
```bash
docker ps -a | grep -i oauth
docker ps -a | grep -i shim
```

**If it exists, check its logs:**
```bash
docker logs <oauth-shim-container-name> --tail 50
```

**Check if OAuth shim is in compose file:**
```bash
grep -A 20 'oauth' /opt/obsidian-remote/run_obsidian_remote.yml
```

### Task 4: Verify Nginx MCP Configuration

**Check nginx config for MCP endpoints:**
```bash
grep -r "mcp" /etc/nginx/
cat /etc/nginx/sites-enabled/* | grep -A 20 -B 5 "mcp"
```

**Specifically check:**
- Is there a `/mcp/sse` location block?
- Is there a `/mcp/messages/` location block?
- Is there an `if` statement checking for API key only?
- Does it forward to `organizerserver:3000` or to an OAuth shim?
- Are there any OAuth-related proxy settings?

**Check what happens to Authorization header:**
```bash
grep -i "authorization" /etc/nginx/sites-enabled/*
```

### Task 5: Test MCP Endpoints Directly

**Test from inside the container:**
```bash
# First, get a valid API key from container env
API_KEY=$(docker exec obsremote-organizerserver-1 env | grep MCP_API_KEY | cut -d= -f2)

# Test SSE with API key
docker exec obsremote-organizerserver-1 curl -s -N \
  -H "Authorization: Bearer $API_KEY" \
  http://localhost:3000/sse 2>&1 | head -20 &
sleep 2
kill %1 2>/dev/null

# Check if MCP port is listening
docker exec obsremote-organizerserver-1 netstat -tlnp | grep 3000
```

**Test from production host:**
```bash
# Test via nginx (should use OAuth token)
curl -s -N \
  -H "Authorization: Bearer <TOKEN_FROM_LOCAL_AGENT>" \
  https://alanhoangnguyen.com/mcp/sse 2>&1 | head -10 &
sleep 3
kill %1 2>/dev/null
```

### Task 6: Check Keycloak Token Validation

**Verify the JWKS endpoint is accessible from MCP container:**
```bash
docker exec obsremote-organizerserver-1 curl -s \
  https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/certs | head -20
```

**Test token introspection:**
```bash
# Get a fresh token for testing (or use one from local testing)
# Check if MCP server can validate the token
```

### Task 7: Verify SSE Endpoint Paths

**Check what paths the MCP server exposes:**
```bash
# Look for SSE app setup in MCP server code
docker exec obsremote-organizerserver-1 grep -r "sse" /app/mcp_server/ 2>/dev/null || \
docker exec obsremote-organizerserver-1 find / -name "server.py" -path "*mcp*" 2>/dev/null | head -5
```

---

## Questions for Production Agent

1. **What is the actual architecture?**
   - Is there an OAuth shim between nginx and MCP server?
   - Or does nginx forward directly to MCP server?
   - What is the request flow: Client → Nginx → ? → MCP Server

2. **What authentication is expected at each layer?**
   - Nginx level: API key? OAuth? Both?
   - MCP server level: API key? OAuth? Both?
   - OAuth shim (if exists): What does it do?

3. **Is the MCP server actually running SSE transport?**
   - Check logs for "Starting MCP Inventory Server" with transport type
   - Check if port 3000 is listening

4. **Are there any nginx errors when connecting with OAuth token?**
   ```bash
   tail -50 /var/log/nginx/error.log | grep -i mcp
   ```

5. **What is the current working configuration?**
   - Was MCP ever tested with OAuth?
   - Was it only tested with API key?
   - What is the expected Authorization header format?

---

## Test Token for Debugging

Here is a valid OAuth token obtained during testing (expires soon):
```
eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJoSEhYeS1WLUJoazRPRGQyN2RiZjliOUJuNW0ycVNHZzFzZlBLanJoLVhnIn0.eyJleHAiOjE3Njk4ODI5OTgsImlhdCI6MTc2OTg4MjY5OCwiYXV0aF90aW1lIjoxNzY5ODgyNjA2LCJqdGkiOiI3MmM3NjdmMi01OWVlLTQwNjYtYmIwNi00NmYxZTQwZWU0ZWMiLCJpc3MiOiJodHRwczovL2F1dGguYWxhbmhvYW5nbmd1eWVuLmNvbS9yZWFsbXMvbWNwIiwiYXVkIjpbImh0dHBzOi8vYWxhbmhvYW5nbmd1eWVuLmNvbS9tY3AiLCJhY2NvdW50Il0sInN1YiI6Ijk3NGU0NDM0LTVhNWQtNDk5NS04MmZmLTg0MGFkMzE4MWY0ZSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImNoYXRncHQtbWNwLWNsaWVudCIsInNpZCI6ImU5OThhYjU4LWUxOTEtNGFkYy04MGY4LTcyZTY3NjY2ODI2MCIsImFjciI6IjAiLCJhbGxvd2VkLW9yaWdpbnMiOlsiaHR0cHM6Ly9jbGF1ZGUuYWkiLCJodHRwczovL2NoYXQub3BlbmFpLmNvbSIsImh0dHA6Ly9sb2NhbGhvc3Q6KiIsImh0dHBzOi8vY2hhdGdwdC5jb20iLCJodHRwczovL2FsYW5ob2FuZ25ndXllbi5jb20iXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtbWNwIiwib2ZmbGluZV9hY2Nlc3MiLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7ImFjY291bnQiOnsicm9sZXMiOlsibWFuYWdlLWFjY291bnQiLCJtYW5hZ2UtYWNjb3VudC1saW5rcyIsInZpZXctcHJvZmlsZSJdfX0sInNjb3BlIjoib3BlbmlkIGVtYWlsIHByb2ZpbGUiLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibmFtZSI6InRlc3QgdGVzdCIsInByZWZlcnJlZF91c2VybmFtZSI6Im1jcC10ZXN0ZXItMTc2OTg3OTY3NCIsImdpdmVuX25hbWUiOiJ0ZXN0IiwiZmFtaWx5X25hbWUiOiJ0ZXN0IiwiZW1haWwiOiJtY3AtdGVzdGVyLTE3Njk4Nzk2NzRAdGVzdC5sb2NhbCJ9.xM_ZqkD1eNHDspM92AUMr4yTY8RsJGLuRoFPd8A2WgIjhNn4DlOdJsyxPGgpiu9v3aFD7fo0jdwqGqk0yGxBOErbizUi2SqQ9cPoigDqHM54Xw7tHTmIJlrU5yVTJbkF1yChWHO3NEDsfMqYQgjfgZH7msatgH21hshuC7DlWlxXUcpngXtl2WSiPxTypoP-aIoyvT3UYIhwGUkoOdTFNzxBJ2jgnS5l_6IEamCdUc69nnjQPID5LcpTv7J0rLwcJpqjUN_W8awEKje-dgfsVZU6JXJ2QqWoZbIrEH9BIHLQI2KYBo4gx_8HhM0vDJpFFhtj6qqXrCNukaqd2mwQWA
```

Token claims:
- `iss`: `https://auth.alanhoangnguyen.com/realms/mcp`
- `aud`: `https://alanhoangnguyen.com/mcp`, `account`
- `scope`: `openid email profile`
- `preferred_username`: `mcp-tester-1769879674`

---

## Expected Results

**What we need to know:**
1. Is MCP server configured for OAuth or API key (or both)?
2. What is blocking OAuth tokens from reaching the MCP server?
3. What changes are needed to make OAuth work?
4. Is there an OAuth shim that should be running?

**Ideal outcome:**
- OAuth tokens accepted at `/mcp/sse`
- SSE events received when connecting with valid OAuth token
- Tools list returned via MCP protocol

---

## Files to Check

```
/opt/obsidian-remote/run_obsidian_remote.yml
/etc/nginx/sites-enabled/*
/etc/nginx/nginx.conf
/var/log/nginx/error.log
/root/Orchestration/docs/* (for any existing MCP docs)
```

---

## Contact

Local testing agent will be available to test fixes once deployment changes are made.

Test command for verification:
```bash
curl -N https://alanhoangnguyen.com/mcp/sse \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Accept: text/event-stream"
```

---

**Created:** 2026-01-31
**Request ID:** mcp-oauth-investigation-2026-01-31
