# MCP OAuth Infrastructure - Bridge to Tomorrow

**Date:** 2026-02-03
**Task:** Production OAuth & Infrastructure for Claude MCP Integration
**Reference:** `/root/Orchestration/docs/mcp-oauth-infrastructure-production-agent.md`

---

## Where We Are

### Completed

- [x] Read and understood the full implementation plan
- [x] Pulled organizerserver v0.2.0 image
- [x] Updated `ORGANIZER_VERSION=0.2.0` in `dev/docker-compose.env`
- [x] Changed `MCP_TRANSPORT=sse` to `MCP_TRANSPORT=streamable-http` in `run_obsidian_remote.yml`
- [x] Set `GIT_SYNC_ENABLED=false` as workaround for git sync issue
- [x] Deployed organizerserver with new configuration
- [x] Documented startup issues for organizer team

### Blocked

The organizerserver container is in a restart loop due to **Java OrganizerServer issues** (not MCP transport issues):

1. **Duplicate inventory key** - Container ID `4` appears twice in data
2. **Git sync on unborn branch** - Workaround applied (disabled)

The MCP Streamable HTTP transport **is working** - logs show successful startup before Java crash.

---

## Current Configuration State

**`dev/docker-compose.env`:**
```bash
ORGANIZER_VERSION=0.2.0
GIT_SYNC_ENABLED=false
```

**`run_obsidian_remote.yml` (organizerserver service):**
```yaml
- MCP_TRANSPORT=streamable-http
```

**Container Status:**
```
obsremote-organizerserver-1   Restarting   registry.alanhoangnguyen.com/admin/organizerserver:0.2.0
```

---

## What's Left (6 Production Tasks)

Once organizerserver is stable, proceed with these tasks from the implementation plan:

### Task 1: Solve Keycloak Admin Access
- **Status:** NOT STARTED
- **Priority:** CRITICAL - blocks Tasks 2, 6
- Try Option A: Reset admin password
- Verify can login to https://auth.alanhoangnguyen.com

### Task 2: Add Claude Redirect URIs to Keycloak
- **Status:** NOT STARTED
- **Depends on:** Task 1
- Add `https://claude.ai/api/mcp/auth_callback`
- Add `https://claude.com/api/mcp/auth_callback`

### Task 3: Create OAuth Discovery Endpoint
- **Status:** NOT STARTED
- **File:** `custom_server.conf`
- Add `/.well-known/oauth-authorization-server` location block
- Proxy to Keycloak OIDC discovery

### Task 4: Update Nginx Routing for Streamable HTTP
- **Status:** NOT STARTED
- **Depends on:** organizerserver stable
- **File:** `custom_server.conf`
- Remove old `/mcp/sse` and `/mcp/messages/` routes
- Add single `/mcp` route to jwt_validator

### Task 5: Verify JWT Validator for Streamable HTTP
- **Status:** NOT STARTED
- Current version: v1.0.9 (has SSE streaming fix)
- Should work for Streamable HTTP (also uses SSE for responses)
- Test after Task 4 completes

### Task 6: Optional - Enable Dynamic Client Registration
- **Status:** NOT STARTED
- **Depends on:** Task 1
- Not required for MVP

---

## Files Modified This Session

| File | Change |
|------|--------|
| `dev/docker-compose.env` | `ORGANIZER_VERSION=0.1.3` → `0.2.0`, `GIT_SYNC_ENABLED=true` → `false` |
| `run_obsidian_remote.yml` | `MCP_TRANSPORT=sse` → `streamable-http` |

**Backups created:**
- `dev/docker-compose.env.backup-20260203_*`
- `run_obsidian_remote.yml.backup-20260203_*`

---

## Verification Commands

**Check if organizer team fixed the issue:**
```bash
cd /root/Orchestration/obsRemote
docker ps --filter "name=organizerserver"
# Should show "Up X minutes (healthy)" not "Restarting"
```

**Test MCP endpoint after fix:**
```bash
source script/sourceEnv.sh
docker exec obsremote-organizerserver-1 curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

**Expected response:** Valid JSON-RPC initialize response (not 404 or connection error)

---

## Next Steps When Resuming

1. **Check organizer team status** - Has v0.2.0 duplicate key issue been fixed?
2. **If fixed:** Pull new image, redeploy, verify `/mcp` endpoint works
3. **If not fixed:** Wait or help debug
4. **Once stable:** Proceed with Task 1 (Keycloak admin access)

---

## Related Documentation

- Issue writeup: `docs/task-log/organizerserver-0.2.0-startup-issues-2026-02-03.md`
- Full implementation plan: `/root/Orchestration/docs/mcp-oauth-infrastructure-production-agent.md`
- Local agent migration doc: `/root/Orchestration/docs/mcp-streamable-http-migration-local-agent.md`

---

**Status:** BLOCKED - Waiting for organizerserver v0.2.0 fix
**Blocker Owner:** Organizer team (local development)
**Next Action:** Check if organizer team has fixed the duplicate key issue
