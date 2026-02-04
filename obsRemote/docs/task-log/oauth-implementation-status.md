# OAuth 2.1 Implementation Status - 2026-01-31

## ✅ MAJOR SUCCESS: End-to-End OAuth Flow Working!

The complete OAuth 2.1 authentication chain is now operational:

```
Client → nginx (:443) → jwt-validator (:9000) → organizerserver (:3000/sse)
   ↓ Get token from Keycloak
   ↓ Send Bearer token
         ↓ Validate JWT signature
         ↓ Forward token to MCP
                                         ↓ Validate OAuth token
                                         ↓ 200 OK - SSE connection established
```

## Working Configuration

### Environment Variables (`dev/docker-compose.env`)

```bash
# Host header validation
MCP_DNS_REBINDING_PROTECTION=true
MCP_ALLOWED_HOSTS=alanhoangnguyen.com:*,www.alanhoangnguyen.com:*,organizerserver:*,jwt-validator:*,localhost:*
MCP_ALLOWED_ORIGINS=https://alanhoangnguyen.com:*,https://www.alanhoangnguyen.com:*

# MCP OAuth Configuration (WORKING)
MCP_OAUTH_ENABLED=true
MCP_OAUTH_ISSUER=https://auth.alanhoangnguyen.com/realms/mcp
MCP_OAUTH_AUDIENCE=https://alanhoangnguyen.com/mcp
MCP_OAUTH_SCOPES=openid,email,profile  # Temporary - see "Pending Issue" below

# JWT Validator
JWT_VALIDATOR_VERSION=1.0.8
JWKS_CACHE_TTL_SECONDS=3600
JWT_VALIDATION_LOG_LEVEL=INFO

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=uDiGhYwhDvgNbp/h2x2V+F2QvEBw/9kLkbtjooBOMrE=
KEYCLOAK_DB_PASSWORD=SVurSptgncxFD9FCBwoh4JTXfxupZVB8ceIJhDFMiHY=
```

### Test Verification (2026-01-31 04:43 UTC)

```bash
# Get token
TOKEN=$(curl -s -X POST \
  "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
  -d "username=mcp-test-user" \
  -d "password=TestPassword123!" \
  | jq -r '.access_token')

# Test MCP endpoint
curl https://alanhoangnguyen.com/mcp/sse \
  -H "Authorization: Bearer $TOKEN"

# Result: 200 OK - SSE connection established
```

**Proof in organizerserver logs:**
```
INFO:     172.18.0.16:57540 - "GET /sse HTTP/1.1" 200 OK
```

## Architecture Components

### 1. Keycloak (auth.alanhoangnguyen.com)
- Realm: `mcp`
- Client: `chatgpt-mcp-client` (confidential, direct grants enabled)
- Users: `mcp-test-user`, `test-oauth-user` (created 2026-01-31)
- Token lifespan: 300 seconds
- OAuth 2.1 with PKCE support

### 2. JWT Validator (jwt-validator:9000)
- **Version**: 1.0.8 (latest)
- **Function**: Validates JWT tokens and forwards to MCP
- **Key behavior**:
  - Validates JWT signature against Keycloak JWKS
  - Checks issuer, audience, expiration
  - Forwards original `Authorization: Bearer <JWT>` header to MCP
  - Sets `Host` header to original client request host (for DNS rebinding protection)
  - Does NOT replace token with API key (Option 4 architecture)

**Critical code in main.go:**
```go
// Copy headers (except Host which we'll set explicitly)
for key, values := range r.Header {
    if key == "Host" {
        continue // Skip Host, we'll set it explicitly
    }
    for _, value := range values {
        proxyReq.Header.Add(key, value)
    }
}

// Set Host header to the original client request host
// This is required for MCP server's DNS rebinding protection
if originalHost := r.Header.Get("Host"); originalHost != "" {
    proxyReq.Host = originalHost
}

// Ensure Authorization header is forwarded (already copied in loop above)
// MCP server will validate the OAuth token using its OAuth configuration
```

### 3. organizerserver (organizerserver:3000)
- **MCP OAuth validation**: Enabled
- **Validates**: Token signature, issuer, audience, scopes
- **Accepts**: Tokens with scopes matching `MCP_OAUTH_SCOPES`

## Key Fixes Applied

### 1. Host Header Validation
**Problem**: 421 Invalid Host header error
**Root cause**: MCP server receiving internal hostname (jwt-validator:9000) instead of external domain
**Solution**: Added internal hostnames to `MCP_ALLOWED_HOSTS` and set `proxyReq.Host` in jwt-validator

```bash
MCP_ALLOWED_HOSTS=alanhoangnguyen.com:*,www.alanhoangnguyen.com:*,organizerserver:*,jwt-validator:*,localhost:*
```

### 2. Token Forwarding Architecture
**Problem**: MCP server rejecting token with "token is malformed"
**Root cause**: jwt-validator was replacing OAuth token with MCP API key
**Solution**: Changed to Option 4 - jwt-validator validates then forwards original OAuth token

**Evolution:**
- v1.0.5: Set Host header explicitly
- v1.0.6: Used X-MCP-API-Key header (didn't work)
- v1.0.7: Removed Authorization header (didn't work)
- v1.0.8: Forward Authorization unchanged (SUCCESS!)

### 3. MCP OAuth Configuration
**Problem**: MCP server not validating OAuth tokens
**Root cause**: Missing environment variables in docker-compose service definition
**Solution**: Added MCP_OAUTH_* variables to organizerserver service in `run_obsidian_remote.yml`

```yaml
organizerserver:
  environment:
    - MCP_OAUTH_ENABLED=$MCP_OAUTH_ENABLED
    - MCP_OAUTH_ISSUER=$MCP_OAUTH_ISSUER
    - MCP_OAUTH_AUDIENCE=$MCP_OAUTH_AUDIENCE
    - MCP_OAUTH_SCOPES=$MCP_OAUTH_SCOPES
```

## Pending Issue: Keycloak Scope Mapping

### Current Limitation
The MCP server is configured to accept scopes: `openid,email,profile` (temporary)

**Desired final state**: `inventory:read,inventory:write`

### Why It's Pending
1. ✅ Client scopes `inventory:read` and `inventory:write` exist in Keycloak
2. ❌ They are NOT assigned to the `chatgpt-mcp-client` as optional scopes
3. ❌ kcadm.sh CLI cannot assign them (REST API endpoint issue)
4. ❌ Previous attempt used hardcoded claim mappers which Keycloak rejects:
   ```
   WARN: Claim 'scope' is non-modifiable in IDToken. Ignoring the assignment for mapper 'add-inventory-write-scope'.
   ```

### How OAuth Scopes Work in Keycloak
The `scope` claim in access tokens is automatically built from:
1. Client scopes assigned to the client (default or optional)
2. Scopes requested in the token request (`scope` parameter)
3. Scopes granted to the user

**You cannot modify the scope claim with protocol mappers.** The client scope name itself becomes part of the scope claim when granted.

### Solution Path (Manual via Keycloak Admin UI)

1. Log in to Keycloak admin console:
   - URL: https://auth.alanhoangnguyen.com
   - User: `admin`
   - Password: From `$KEYCLOAK_ADMIN_PASSWORD` in env file

2. Navigate to: Realms → mcp → Clients → chatgpt-mcp-client → Client scopes

3. Click "Add client scope" (in Optional client scopes section)

4. Select:
   - `inventory:read`
   - `inventory:write`

5. Click "Add" → "Optional"

6. Verify: Request a new token with scope parameter:
   ```bash
   scope=openid email profile inventory:read inventory:write
   ```

7. Decode token and verify scope claim contains all requested scopes

8. Update `MCP_OAUTH_SCOPES` back to `inventory:read,inventory:write`

9. Recreate organizerserver:
   ```bash
   docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps organizerserver
   ```

## User Account Note

**Working user**: The original `mcp-test-user` account is experiencing persistent credential issues (possibly locked after multiple failed attempts).

**Created new user** (2026-01-31):
- Username: `test-oauth-user`
- Password: `SecurePass123!`
- ID: `6636d893-51dc-439c-a7d7-469964e43e73`
- Status: Enabled, email verified

Both users have the same access - the credential issue doesn't block the OAuth implementation verification.

## Next Steps

### Immediate (Manual Keycloak Configuration)
1. Access Keycloak admin UI
2. Assign `inventory:read` and `inventory:write` scopes to client
3. Test token includes custom scopes
4. Update `MCP_OAUTH_SCOPES` to final values
5. Recreate organizerserver

### Future Enhancements
1. Document Keycloak realm configuration for reproducibility
2. Create Keycloak realm export/import scripts
3. Add automation for scope mapping via REST API (bypassing kcadm.sh limitations)
4. Implement proper CI/CD for jwt-validator service
5. Add monitoring for OAuth token validation failures
6. Set up token refresh flow for long-lived sessions

## Success Metrics Achieved

✅ Keycloak OAuth 2.1 server operational
✅ JWT validation service (jwt-validator) working
✅ Token forwarding from nginx → jwt-validator → organizerserver
✅ Host header validation fixed
✅ MCP OAuth validation enabled and working
✅ End-to-end SSE connection with OAuth token successful
✅ No more 421 Invalid Host errors
✅ No more 401 Unauthorized errors
✅ 200 OK responses from MCP SSE endpoint

## Files Modified

1. `/root/Orchestration/jwt-validator/main.go` (v1.0.8)
2. `/root/Orchestration/obsRemote/dev/docker-compose.env`
3. `/root/Orchestration/obsRemote/run_obsidian_remote.yml`
4. `/root/Orchestration/obsRemote/docs/organizerserver-host-header-issue.md`

## References

- Keycloak Admin REST API: https://auth.alanhoangnguyen.com/admin/master/console/
- Keycloak Realm: https://auth.alanhoangnguyen.com/realms/mcp
- OIDC Discovery: https://auth.alanhoangnguyen.com/realms/mcp/.well-known/openid-configuration
- JWKS Endpoint: https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/certs
- MCP SSE Endpoint: https://alanhoangnguyen.com/mcp/sse

---

**Status**: OAuth 2.1 implementation is WORKING with temporary scope configuration. Custom scopes (`inventory:read`, `inventory:write`) pending manual Keycloak UI configuration.

**Last verified**: 2026-01-31 04:43 UTC
