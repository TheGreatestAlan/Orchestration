# OrganizerServer v0.2.0 Startup Issues

**Date:** 2026-02-03
**Reporter:** Production Agent
**Severity:** HIGH - Service won't start
**Component:** organizerserver (Java OrganizerServer component)
**Version:** 0.2.0

---

## Summary

After deploying organizerserver v0.2.0 with Streamable HTTP transport, the container enters a restart loop. The **MCP server (Python) starts successfully**, but the **Java OrganizerServer crashes** due to data issues, which then terminates the entire container.

---

## What's Working

The MCP Streamable HTTP transport is correctly configured and starts up:

```
2026-02-03 20:26:27,262 - __main__ - INFO - Transport: streamable-http
2026-02-03 20:26:27,262 - __main__ - INFO - Starting Streamable HTTP transport on /mcp endpoint
2026-02-03 20:26:27,294 - mcp.server.streamable_http_manager - INFO - StreamableHTTP session manager started
INFO:     Uvicorn running on http://0.0.0.0:3000 (Press CTRL+C to quit)
```

---

## Issue 1: Duplicate Key in Inventory Data

**Error:**
```
java.lang.IllegalStateException: Duplicate key 4 (attempted merging values [Thyme, Turmeric, Marjoram Leaves, taco seasoning mix] and [Thyme, Turmeric, Parsley, Cumin Seed, Marjoram Leaves, taco seasoning mix])
	at java.base/java.util.stream.Collectors.duplicateKeyException(Unknown Source)
	at com.nguyen.server.repository.FileSystemRepository.getOrganizerInventory(FileSystemRepository.java:36)
	at com.nguyen.server.services.Inventory.<init>(Inventory.java:18)
```

**Root Cause:**
The inventory data files contain duplicate container IDs (key `4` appears twice with different contents).

**Location:**
`FileSystemRepository.java:36` - The code uses `Collectors.toMap()` which throws on duplicate keys.

**Suggested Fix Options:**

1. **Data fix:** Remove duplicate entries from inventory files
2. **Code fix:** Use `Collectors.toMap()` with merge function to handle duplicates:
   ```java
   .collect(Collectors.toMap(
       Container::getId,
       Container::getItems,
       (existing, replacement) -> replacement  // or merge logic
   ))
   ```

---

## Issue 2: Git Sync Fails on Unborn Branch

**Error (when GIT_SYNC_ENABLED=true):**
```
com.nguyen.server.OrganizerRepositoryException: Sync failed
Caused by: org.eclipse.jgit.api.errors.NoHeadException: Cannot check out from unborn branch
	at org.eclipse.jgit.api.PullCommand.call(PullCommand.java:215)
	at com.nguyen.server.repository.GitRepositoryUtils.syncWithRemote(GitRepositoryUtils.java:42)
```

**Root Cause:**
The git repository mounted into the container has no commits or is in an invalid state.

**Current Workaround:**
Set `GIT_SYNC_ENABLED=false` in `dev/docker-compose.env`

**Suggested Fix:**
Check if repository has HEAD before attempting pull in `GitRepositoryUtils.syncWithRemote()`:
```java
if (git.getRepository().resolve("HEAD") == null) {
    // Skip sync or initialize repository
    return;
}
```

---

## Current Configuration

**Environment:**
```bash
ORGANIZER_VERSION=0.2.0
GIT_SYNC_ENABLED=false  # Disabled as workaround
MCP_TRANSPORT=streamable-http
```

**Container Status:**
```
obsremote-organizerserver-1   Restarting (1)   registry.alanhoangnguyen.com/admin/organizerserver:0.2.0
```

---

## Impact

- **MCP Integration Blocked:** Cannot proceed with Claude MCP OAuth infrastructure work until this is fixed
- **Inventory API Unavailable:** The Java OrganizerServer provides the inventory API that the MCP server depends on

---

## Recommended Priority

1. **HIGH:** Fix duplicate key issue in `FileSystemRepository.java` or clean inventory data
2. **MEDIUM:** Add defensive handling for unborn git branches

---

## Files to Investigate

- `FileSystemRepository.java:36` - Duplicate key handling
- `GitRepositoryUtils.java:42` - Git sync error handling
- Inventory data files - Check for duplicate container IDs

---

## Testing After Fix

Once fixed, verify:
```bash
# Container should stay running
docker ps --filter "name=organizerserver"

# Should return healthy
docker exec obsremote-organizerserver-1 curl -s http://localhost:8081/healthcheck

# MCP endpoint should respond
docker exec obsremote-organizerserver-1 curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

---

**Status:** Waiting for organizer team fix
**Blocks:** MCP OAuth infrastructure production work (Tasks 1-6 in mcp-oauth-infrastructure-production-agent.md)
