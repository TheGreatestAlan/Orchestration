# OrganizerServer Java Fix Instructions

## Issue Summary

The Java OrganizerServer crashes on startup due to data issues. These are **NOT related to the MCP Streamable HTTP migration** (which is working correctly).

## Root Causes & Fixes

### Issue 1: Duplicate Container ID in Inventory Data

**Error:**
```
Duplicate key 4 (attempted merging values [Thyme, Turmeric, Marjoram Leaves, taco seasoning mix] and [Thyme, Turmeric, Parsley, Cumin Seed, Marjoram Leaves, taco seasoning mix])
```

**Fix Option A: Clean the data (Recommended - Quick Fix)**

1. Find and edit the inventory data file:
   ```bash
   cd /path/to/obsidian/vault  # or wherever OBSIDIAN_VAULT_REPO_LOCATION points
   find . -name "*.json" -o -name "*.md" | xargs grep -l '"id": *4' 2>/dev/null
   ```

2. Look for duplicate container entries with ID 4 and remove one, OR rename one to a unique ID

3. Restart container:
   ```bash
   cd /root/Orchestration/obsRemote
   docker compose -f run_obsidian_remote.yml restart organizerserver
   ```

**Fix Option B: Code fix (If data cleanup is difficult)**

If you need me to fix the Java code to handle duplicates gracefully, let me know and I'll update `FileSystemRepository.java` to merge duplicates instead of throwing.

---

### Issue 2: Git Repository Unborn Branch

**Error:**
```
NoHeadException: Cannot check out from unborn branch
```

**Fix:**

1. SSH into the host where the vault volume is mounted

2. Initialize the git repository properly:
   ```bash
   cd /path/to/vault/directory
   git init
   git add .
   git commit -m "Initial commit"
   # If you have a remote:
   # git remote add origin <your-remote-url>
   # git push -u origin main
   ```

3. Or disable git sync (already done):
   ```bash
   GIT_SYNC_ENABLED=false
   ```

---

## Verification After Fix

```bash
# Check container is running
docker ps --filter "name=organizerserver"

# Check Java server health
docker exec obsremote-organizerserver-1 curl -s http://localhost:8081/healthcheck

# Test MCP endpoint
docker exec obsremote-organizerserver-1 curl -s -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## Priority

1. **URGENT:** Fix duplicate key issue (blocks all OrganizerServer functionality)
2. **LOW:** Initialize git repo or keep GIT_SYNC_ENABLED=false

## Notes

- The MCP Streamable HTTP transport is correctly configured and working
- The container exits because Java crashes, not because of MCP issues
- Once Java starts, the full stack (MCP + Java API) should work together
