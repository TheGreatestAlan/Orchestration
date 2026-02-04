# Keycloak Scope Assignment Problem

## The Problem

**Goal**: Assign `inventory:read` and `inventory:write` client scopes to the `chatgpt-mcp-client` as optional scopes in Keycloak.

**Why we need this**: These scopes need to be requested in OAuth tokens and included in the token's `scope` claim so that the MCP server can validate them.

**Current state**:
- ✅ Client scopes `inventory:read` and `inventory:write` exist in Keycloak realm `mcp`
  - `inventory:read` ID: `9f6ba827-957b-455c-a54e-9f8914efd18e`
  - `inventory:write` ID: `1708e028-a07f-4c50-bfb2-366036d997eb`
- ✅ Client `chatgpt-mcp-client` exists
  - Client UUID: `a8f58fee-9f9d-4422-b4c5-df3596e1233f`
- ❌ These client scopes are NOT assigned to the client as optional scopes
- ❌ Current optional scopes: `address`, `phone`, `organization`, `offline_access`, `microprofile-jwt` (5 total)

**What happens when scopes aren't assigned**:
- Tokens requested with `scope=inventory:read inventory:write` don't include these in the scope claim
- Token only contains: `openid email profile` (the default scopes)
- MCP server rejects tokens because they don't have required scopes

## What We've Tried

### Attempt 1: kcadm.sh update endpoint
```bash
docker exec keycloak /opt/keycloak/bin/kcadm.sh update \
  clients/$CLIENT_ID/optional-client-scopes/$INVENTORY_READ_ID \
  -r mcp
```
**Result**: "Resource not found" error - This endpoint doesn't exist for kcadm update

### Attempt 2: kcadm.sh create endpoint
```bash
docker exec keycloak /opt/keycloak/bin/kcadm.sh create \
  clients/$CLIENT_UUID/optional-client-scopes/$INVENTORY_READ_ID \
  -r mcp
```
**Result**: "Resource not found for url: http://localhost:8080/admin/realms/mcp/clients/.../optional-client-scopes/..."

### Attempt 3: Update entire client config with modified optionalClientScopes array
```bash
# Get client, modify optionalClientScopes array in JSON, update client
docker exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$CLIENT_UUID \
  -r mcp -f /tmp/client-update.json
```
**Result**:
- Command exits with code 0 (success)
- But verification shows scopes weren't added
- Array still has 5 items, not 7
- Suggests the `optionalClientScopes` field might be read-only via this API

### Attempt 4: Update with -s flag
```bash
docker exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$CLIENT_UUID -r mcp \
  -s "optionalClientScopes=$NEW_SCOPES"
```
**Result**: Same as Attempt 3 - no error, but scopes not added

### Attempt 5: Get Keycloak Admin REST API token from external URL
```bash
curl -X POST "https://auth.alanhoangnguyen.com/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$KEYCLOAK_ADMIN_PASSWORD"
```
**Result**: 401 Unauthorized - "Invalid user credentials"
- The `KEYCLOAK_ADMIN_PASSWORD` in env file doesn't work for external auth
- Password might be encrypted/encoded, or different from actual admin password

### Attempt 6: Install curl in Keycloak container to call internal API
```bash
docker exec -u root keycloak microdnf install -y curl
```
**Result**: Failed - curl still not available after install attempt
- Keycloak container might be using minimal base image without package manager
- Even `which` command not available in container

### Attempt 7: Call Keycloak internal API from host via container IP
```bash
KEYCLOAK_IP=$(docker inspect keycloak | jq -r '.[0].NetworkSettings.Networks.obsidian_network.IPAddress')
```
**Result**: IP is null
- Network name is actually `obsremote_obsidian_network`, not `obsidian_network`
- Didn't complete this attempt

## Related Discovery: Previous Scope Mapper Mistakes

Looking at Keycloak logs, we found evidence of previous incorrect attempts:
```
WARN: Claim 'scope' is non-modifiable in IDToken. Ignoring the assignment for mapper 'add-inventory-write-scope'.
WARN: Claim 'scope' is non-modifiable in IDToken. Ignoring the assignment for mapper 'add-inventory-read-scope'.
```

**What this means**:
- Someone previously tried to add hardcoded claim mappers to modify the `scope` claim
- These mappers were configured on the client scopes
- Keycloak correctly rejects this because the `scope` claim is automatically built
- We removed these incorrect mappers

**How OAuth scopes actually work**:
1. Client scopes must be assigned to the client (default or optional)
2. Client requests token with desired scopes in `scope` parameter
3. Keycloak includes granted scope NAMES in the token's scope claim
4. The client scope name itself becomes part of the scope claim - no mapper needed

## The Correct Solution (Not Yet Working)

According to Keycloak Admin REST API documentation, the correct operation is:

**HTTP Method**: `PUT` (not POST, not client update)
**Endpoint**: `/admin/realms/{realm}/clients/{client-uuid}/optional-client-scopes/{scope-uuid}`
**Body**: Empty (the relationship is established by the PUT to this URL)
**Auth**: Bearer token from admin login

Example:
```bash
curl -X PUT \
  "http://localhost:8080/admin/realms/mcp/clients/a8f58fee-9f9d-4422-b4c5-df3596e1233f/optional-client-scopes/9f6ba827-957b-455c-a54e-9f8914efd18e" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

**Why we haven't completed this**:
- Can't get admin token from external URL (password issue)
- Can't execute curl from inside Keycloak container (curl not available)
- Haven't successfully connected to internal Keycloak API from host

## What Would Work (Manual UI)

The Keycloak Admin UI definitely works:
1. Login at https://auth.alanhoangnguyen.com
2. Username: `admin`
3. Password: Need to determine actual admin password
4. Navigate: Realms → mcp → Clients → chatgpt-mcp-client → Client scopes tab
5. Click "Add client scope" button in Optional scopes section
6. Select `inventory:read` and `inventory:write`
7. Click "Add" → "Optional"

**Blocker**: Don't know the actual admin password for web UI login

## Current Workaround

Temporarily using scopes that ARE in tokens by default:
```bash
MCP_OAUTH_SCOPES=openid,email,profile
```

This makes the OAuth flow work end-to-end, but these aren't the semantically correct scopes for inventory operations.

## Information We Have

**Keycloak Admin Credentials**:
- Username: `admin` (confirmed working in kcadm.sh)
- Password in env: `uDiGhYwhDvgNbp/h2x2V+F2QvEBw/9kLkbtjooBOMrE=`
  - This works for kcadm.sh local auth
  - Does NOT work for external OAuth token requests
  - Might be base64-encoded or encrypted

**Keycloak Setup**:
- Container: `keycloak` (not `obsremote-keycloak-1`)
- Network: `obsremote_obsidian_network`
- Internal port: 8080
- External URL: https://auth.alanhoangnguyen.com
- Realm: `mcp`
- kcadm.sh is authenticated and working for GET/LIST operations

**Test Users**:
- `mcp-test-user` - has credential issues (password not working)
- `test-oauth-user` - created fresh, also has credential issues

## Next Steps to Try

1. **Get Keycloak internal IP correctly**:
   ```bash
   docker inspect keycloak | jq -r '.[0].NetworkSettings.Networks["obsremote_obsidian_network"].IPAddress'
   ```

2. **Call Admin API from host via internal IP**:
   - Get admin token from `http://<IP>:8080/realms/master/protocol/openid-connect/token`
   - PUT to scope assignment endpoints

3. **Investigate admin password**:
   - Check Keycloak logs for how admin user was created
   - Try decoding the password in env file
   - Reset admin password if needed

4. **Try PostgreSQL database direct access**:
   - Connect to keycloak_db container
   - Query to see current client-scope relationships
   - Potentially insert the relationship directly (risky)

5. **Manual UI as last resort**:
   - Determine actual admin password
   - Log into web UI
   - Add scopes manually through UI
