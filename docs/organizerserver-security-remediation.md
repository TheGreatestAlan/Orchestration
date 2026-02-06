# OrganizerServer Security Remediation - INTERNAL ONLY

**Date:** 2026-02-05
**Priority:** HIGH
**Status:** Action Required

---

## Issue Summary

The OrganizerServer API endpoints are currently exposed to the internet through nginx proxy rules. This is a security risk as the inventory API has no authentication.

**Current Exposure:**
- `organizerserver:8080/` - Full inventory API exposed
- `organizerserver:3000/mcp` - MCP endpoint exposed
- `organizerserver:3000/sse` - SSE endpoint exposed
- `organizerserver:3000/messages/` - Messages endpoint exposed

**Risk:** Anyone can access/modify inventory data without authentication.

---

## Required Changes

### 1. Remove Direct API Exposure

In `/root/Orchestration/obsRemote/custom_server.conf`, remove or comment out:

```nginx
# REMOVE THIS LINE:
proxy_pass http://organizerserver:8080/;

# KEEP THESE (MCP access):
proxy_pass http://organizerserver:3000/mcp;
proxy_pass http://organizerserver:3000/sse;
proxy_pass http://organizerserver:3000/messages/;
```

The MCP server on port 3000 should be the ONLY entry point.

### 2. Restrict Internal Access

If other services need inventory access, they should use the Docker network:

```yaml
# For agent-server or other internal services:
environment:
  - INVENTORY_API_BASE_URL=http://organizerserver:8080
```

NOT via external URLs.

### 3. Verify MCP Security

Ensure MCP endpoints have proper authentication:
- `MCP_API_KEY` is set and validated
- `MCP_OAUTH_ENABLED` is properly configured if using OAuth

### 4. Test After Changes

```bash
# Should FAIL (no longer exposed):
curl https://flofluent.com/inventory
curl https://flofluent.com:8080/inventory

# Should SUCCEED (MCP still accessible):
curl https://flofluent.com/mcp
```

---

## Architecture Goal

```
Internet → Nginx → MCP (port 3000) → OrganizerServer API (port 8080)
                    ↑
              (authenticated)
```

NOT:

```
Internet → Nginx → OrganizerServer API (port 8080)
              ↑
        (unauthenticated - BAD)
```

---

## Files to Modify

1. `/root/Orchestration/obsRemote/custom_server.conf`
   - Remove the `organizerserver:8080/` proxy rule
   - Keep only `organizerserver:3000/*` rules

2. After nginx config change:
   ```bash
   cd /root/Orchestration/obsRemote
   docker compose -f run_obsidian_remote.yml restart nginx_proxy_manager
   # OR if nginx is separate:
   nginx -t && nginx -s reload
   ```

---

## Verification Steps

1. **Confirm API is blocked externally:**
   ```bash
   curl -f https://flofluent.com/inventory  # Should return 404 or 403
   ```

2. **Confirm MCP still works:**
   ```bash
   curl -f https://flofluent.com/mcp  # Should return 200 or auth challenge
   ```

3. **Confirm internal access works:**
   ```bash
   docker compose -f run_obsidian_remote.yml exec agent-server \
     curl http://organizerserver:8080/inventory  # Should succeed
   ```

---

## Notes

- The OrganizerServer was recently migrated to H2 database (v0.2.2)
- Database is persisted at `/data/organizer/db/`
- Healthcheck on port 8081 is internal-only (not exposed via nginx) - this is fine
