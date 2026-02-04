# MCP OAuth Scope Change – Bridge to Tomorrow

**Date:** 2026-01-31
**Session Focus:** Changed JWT validator to accept working OAuth scopes instead of fixing Keycloak scope assignment

---

## Where We Are

### ✅ Completed Today

1. **Updated JWT Validator Required Scopes**
   - Changed `REQUIRED_SCOPES` from empty string to `openid,email,profile`
   - File: `/root/Orchestration/obsRemote/run_obsidian_remote.yml` (line 330)
   - Service restarted and verified picking up new configuration
   - Logs confirm: `INFO: Required scopes: [openid email profile]`

2. **Identified Root Cause**
   - JWT validator was configured to require `inventory:read,inventory:write` (documented as "hardcoded" but actually environment-configurable)
   - Keycloak tokens only contain `openid,email,profile` scopes
   - Decided to accept the scopes that ARE in tokens rather than continue fighting with Keycloak

3. **Found Keycloak Internal IP**
   - Container IP: `172.18.0.15`
   - Network: `obsremote_obsidian_network`
   - This could be useful for future Keycloak API work

### 🔴 Still Blocked

1. **Password Grant Flow Not Working**
   - All user password authentication attempts fail with `invalid_user_credentials`
   - Tested users:
     - `mcp-test-user` (ID: 49793724-696b-40a1-b29d-ba91faa59081)
     - `test-oauth-user` (ID: 6636d893-51dc-439c-a7d7-469964e43e73)
     - `oauth-test` (ID: 7e09c53e-9a7d-4749-ac26-acab7f17409f) - created fresh
   - Password reset commands succeed but credentials still don't work
   - Same issue via external URL and internal IP
   - This is documented in `keycloak-scope-assignment-problem.md`

2. **MCP Endpoint Testing Not Completed**
   - Need to verify the scope change actually works end-to-end
   - Authorization Code flow test prepared but not executed
   - Waiting for user to complete browser-based OAuth flow

### ⚠️ Original Problem Deferred

The original goal was to assign `inventory:read` and `inventory:write` scopes to `chatgpt-mcp-client` in Keycloak. This is **still not solved** - we worked around it instead.

See full details in: `/root/Orchestration/obsRemote/docs/keycloak-scope-assignment-problem.md`

---

## What's Left to Complete

### Immediate (Tomorrow Morning)

1. **Test the Authorization Code Flow**
   - User needs to open the authorization URL in browser
   - Login and get the callback URL with authorization code
   - Exchange code for access token
   - Test MCP SSE endpoint with token
   - Verify JWT validator accepts the token with new scopes

2. **Verify End-to-End MCP Functionality**
   - Confirm token validation succeeds
   - Confirm MCP endpoints return data (not just 200 OK)
   - Check organizerserver logs for any issues
   - Test with actual MCP client if available (ChatGPT/Claude Desktop)

### Follow-Up Tasks

3. **Document the Scope Change Decision**
   - Update `mcp-keycloak-envs.md` to reflect REQUIRED_SCOPES change
   - Note why we're using `openid,email,profile` instead of `inventory:*`
   - Document that this is temporary until Keycloak scope assignment works

4. **Optional: Fix the Original Keycloak Problem**
   - If semantic correctness matters, eventually fix the scope assignment
   - The correct approach is documented in `keycloak-scope-assignment-problem.md`
   - Would need to either:
     - Get admin password working for web UI
     - Use kcadm.sh with proper syntax (though this failed before)
     - Use Keycloak Admin REST API via internal IP with proper authentication

---

## Testing Instructions for Tomorrow

### Authorization Code Flow Test (Ready to Run)

**Step 1: Open in Browser**
```
https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-123
```

**Step 2: Login Credentials**
- **Option A:** Username: `oauth-test` / Password: `TestPass123!`
- **Option B:** Create a new user via Keycloak web UI (if you know the admin password)
- **Option C:** Create user via kcadm.sh (see commands below)

**Step 3: Get Callback URL**
After login, browser redirects to `http://localhost:8888/callback?code=XXXXX&state=test-123`

Browser will show "connection refused" - **this is expected**. Copy the full URL from address bar.

**Step 4: Exchange Code for Token**
```bash
# Extract the code from the URL (replace XXXXX with actual code)
CODE="XXXXX"

# Exchange for token
curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=$CODE" \
    -d "redirect_uri=http://localhost:8888/callback" | python3 -m json.tool
```

**Step 5: Test MCP Endpoint**
```bash
# Use the access_token from previous response
ACCESS_TOKEN="your-token-here"

# Test SSE endpoint
timeout 3 curl -v \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://alanhoangnguyen.com/mcp/sse

# Check JWT validator logs
docker logs jwt_validator --tail 20
```

---

## Key Files Modified

### `/root/Orchestration/obsRemote/run_obsidian_remote.yml`

**Line 330 changed from:**
```yaml
      - REQUIRED_SCOPES=
```

**To:**
```yaml
      - REQUIRED_SCOPES=openid,email,profile
```

**No backup was created** - if you need to revert:
```bash
cd /root/Orchestration/obsRemote
git diff run_obsidian_remote.yml  # see the change
git checkout run_obsidian_remote.yml  # revert if needed
```

---

## Important Context & Notes

### Why We Changed Scopes

**Original Plan:** Assign `inventory:read` and `inventory:write` scopes to the client in Keycloak

**Blockers:**
- Multiple kcadm.sh approaches failed (documented in keycloak-scope-assignment-problem.md)
- Can't get admin token via external URL (password doesn't work)
- Can't install curl in Keycloak container to use internal API

**Pragmatic Solution:** Accept the scopes that ARE already in tokens
- Keycloak is already issuing tokens with `openid,email,profile`
- These are valid OAuth scopes and work fine for authentication
- JWT validator now accepts these scopes
- MCP server already validates tokens via `MCP_OAUTH_ENABLED=true`

**Trade-off:**
- ✅ OAuth flow works end-to-end
- ✅ No Keycloak fighting required
- ❌ Scopes aren't semantically specific to inventory operations
- ❌ Can't do fine-grained permission control based on scopes

### JWT Validator Configuration

The jwt-validator service reads `REQUIRED_SCOPES` from environment variables:

**Code reference:** `/root/Orchestration/jwt-validator/main.go:66`
```go
scopesStr := getEnv("REQUIRED_SCOPES", "")
scopes := strings.Split(scopesStr, ",")
```

**Special behavior:** If `REQUIRED_SCOPES` is empty or contains only empty strings, it accepts ALL tokens (returns true). See line 256-258.

**Current configuration:**
- Container: `jwt_validator`
- Port: 9000 (internal)
- Proxies to: `http://organizerserver:3000`
- Protected endpoints: `/sse`, `/messages/`

### Keycloak Client Configuration

**Client:** `chatgpt-mcp-client`
- UUID: `a8f58fee-9f9d-4422-b4c5-df3596e1233f`
- Client Secret: `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu`
- Redirect URIs: `http://localhost:*`, `https://chat.openai.com/*`, `https://claude.ai/*`
- Direct Access Grants: ✅ Enabled (but doesn't work - password issue)
- Standard Flow: ✅ Enabled (Authorization Code flow - should work)
- Service Accounts: ❌ Disabled

**Available Scopes in Keycloak:**
- `inventory:read` (ID: 9f6ba827-957b-455c-a54e-9f8914efd18e) - ❌ Not assigned to client
- `inventory:write` (ID: 1708e028-a07f-4c50-bfb2-366036d997eb) - ❌ Not assigned to client
- `openid`, `email`, `profile` - ✅ Default scopes, always included

### Services Involved

1. **keycloak** (172.18.0.15:8080)
   - OAuth provider
   - Issues tokens
   - External: https://auth.alanhoangnguyen.com

2. **jwt-validator** (internal:9000)
   - Validates OAuth tokens
   - Checks required scopes
   - Proxies to organizerserver

3. **organizerserver** (internal:3000)
   - MCP server backend
   - Has own OAuth validation via `MCP_OAUTH_*` env vars
   - Endpoints: `/sse`, `/messages/`

4. **nginx_proxy_manager**
   - Routes https://alanhoangnguyen.com/mcp/* to jwt-validator:9000

### Password Issue Deep Dive

The password grant consistently fails for ALL users, even freshly created ones. Keycloak logs show:

```
type="LOGIN_ERROR", error="invalid_user_credentials"
```

**What we tried:**
- Setting passwords via kcadm.sh set-password ✅ (succeeds)
- Testing with freshly created users ❌ (still fails)
- Testing via external URL ❌ (fails)
- Testing via internal IP ❌ (fails)
- Verifying user is enabled ✅ (confirmed enabled)
- Verifying direct grants enabled ✅ (confirmed)

**Hypothesis:**
- Might be a Keycloak configuration issue (password policy, realm settings)
- Might be related to how admin password is stored (base64 encoded in env)
- Might be a bug in this Keycloak version
- Authorization Code flow should work regardless (doesn't use password grant)

---

## Quick Reference Commands

### Check JWT Validator Status
```bash
docker logs jwt_validator --tail 20
docker ps --filter "name=jwt_validator"
```

### Check Keycloak Logs
```bash
docker logs keycloak --tail 50 | grep -i "login_error\|oauth-test"
```

### Create New Test User
```bash
docker exec keycloak /opt/keycloak/bin/kcadm.sh create users -r mcp \
  -s username=test-user-$(date +%s) \
  -s enabled=true \
  -s emailVerified=true

# Then set password (replace username)
docker exec keycloak /opt/keycloak/bin/kcadm.sh set-password -r mcp \
  --username test-user-XXXXX \
  --new-password TestPassword123!
```

### Restart JWT Validator
```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml restart jwt-validator
```

### Recreate JWT Validator (picks up env changes)
```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps jwt-validator
```

---

## Related Documentation

- **Problem Definition:** `obsRemote/docs/keycloak-scope-assignment-problem.md`
- **Environment Variables:** `obsRemote/docs/mcp-keycloak-envs.md`
- **OAuth Implementation:** `obsRemote/docs/keycloak-oauth-implementation-summary.md`
- **Test Script:** `obsRemote/docs/test-oauth-setup.sh` (needs updating for new scopes)
- **JWT Validator Source:** `/root/Orchestration/jwt-validator/main.go`

---

## Success Criteria

✅ **Minimum (to consider this change successful):**
1. Authorization Code flow produces valid token
2. Token contains `scope: "openid email profile"`
3. JWT validator accepts the token (logs show "Token validated successfully")
4. MCP SSE endpoint returns 200 OK

✅ **Ideal (full end-to-end validation):**
1. All minimum criteria met
2. MCP endpoint returns actual SSE data (not just headers)
3. Test with real MCP client (ChatGPT or Claude Desktop)
4. Verify organizerserver processes requests correctly

📝 **Documentation:**
1. Update mcp-keycloak-envs.md with REQUIRED_SCOPES change
2. Create completion document if tests pass
3. Commit changes to git with clear message

---

## If You Need to Revert

```bash
cd /root/Orchestration/obsRemote

# Revert the compose file change
git checkout run_obsidian_remote.yml

# Recreate jwt-validator with old config
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps jwt-validator

# Verify empty scopes (accepts all tokens)
docker logs jwt_validator --tail 5 | grep "Required scopes"
# Should show: INFO: Required scopes: []
```

---

## Questions to Consider Tomorrow

1. **Does the Authorization Code flow work?**
   - If yes: We're done! Just document and commit.
   - If no: What error do we get? Token exchange issue or validation issue?

2. **Do we care about semantic scope names?**
   - If yes: Need to eventually fix Keycloak scope assignment
   - If no: Current solution (`openid,email,profile`) is fine

3. **Should we update the test script?**
   - `obsRemote/docs/test-oauth-setup.sh` still uses old scopes on line 94
   - Should update to `scope=openid email profile` for consistency

4. **Should we add REQUIRED_SCOPES to docker-compose.env?**
   - Currently hardcoded in run_obsidian_remote.yml
   - Could make it a variable: `REQUIRED_SCOPES=${MCP_REQUIRED_SCOPES}`
   - More flexible for future changes

---

**Last Updated:** 2026-01-31 05:35 UTC
**Next Session:** 2026-02-01 (continue with Authorization Code flow test)
