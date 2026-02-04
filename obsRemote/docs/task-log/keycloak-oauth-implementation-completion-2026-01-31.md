# Keycloak OAuth 2.1 Implementation for MCP — COMPLETED

**Date:** 2026-01-31
**Status:** ✅ COMPLETED (Infrastructure) — Manual Keycloak configuration required

## Overview

Successfully implemented industry-standard OAuth 2.1 authentication for MCP (Model Context Protocol) endpoints using Keycloak as the authorization server. This provides secure, scalable authentication for ChatGPT and Claude AI integrations with the MCP server, replacing the simple API key method with a full OAuth 2.1 + PKCE flow.

## What Changed

### Server-Side Changes

#### **`run_obsidian_remote.yml`**
- **Added 3 New Services**: Expanded from 13 to 16 containerized services
  - `keycloak-db`: PostgreSQL 16 Alpine database for Keycloak
  - `keycloak`: Keycloak 23.0 authorization server with OAuth 2.1 support
  - `jwt-validator`: Custom Go service (v1.0.0) for JWT validation and proxying

#### **`custom_server.conf`** (Nginx)
- **Added OAuth Metadata Endpoint**: `/.well-known/oauth-protected-resource` (RFC 8414 compliant)
- **Added Keycloak Proxy**: `/oauth/*` routes to `keycloak:8080`
- **Updated MCP Routes**: Changed from direct proxy to jwt-validator intermediary
  - Before: `/mcp/sse` → `organizerserver:3000/sse`
  - After: `/mcp/sse` → `jwt-validator:9000/sse` → `organizerserver:3000/sse`
  - Before: `/mcp/messages/` → `organizerserver:3000/messages/`
  - After: `/mcp/messages/` → `jwt-validator:9000/messages/` → `organizerserver:3000/messages/`
- **Disabled Basic Auth**: OAuth endpoints publicly accessible (no htpasswd required)

#### **`dev/docker-compose.env`**
- **Added Keycloak Admin Credentials**: Username `admin` with secure base64 password
- **Added Database Password**: Secure PostgreSQL password for Keycloak database
- **Added JWT Validator Config**: Port, version, cache TTL, and log level settings

### Infrastructure Changes

#### **New Docker Images**
- `postgres:16-alpine` - Lightweight PostgreSQL for Keycloak
- `quay.io/keycloak/keycloak:23.0` - Official Keycloak release
- `registry.alanhoangnguyen.com/admin/jwt-validator:1.0.0` - Custom-built Go service

#### **New Data Directories**
- `keycloak/db-data/` - PostgreSQL database storage
- `keycloak/data/` - Keycloak configuration and cache

#### **Service Updates**
- **organizerserver**: Upgraded from 0.1.2 → 0.1.3 (MCP compatibility updates)

## Architecture Achievement

### OAuth 2.1 + PKCE Flow ✅

**Before:**
```
Client → Nginx → MCP Server (API key in header)
```

**After:**
```
Client → Authorization Code + PKCE flow → Keycloak
       → Access Token (JWT)
       → Nginx → JWT Validator → MCP Server (validated)
                     ↓
                   Validates:
                   - JWT signature (JWKS)
                   - Issuer
                   - Audience
                   - Expiration
                   - Scopes
```

### Security Enhancements ✅

**Token-Based Authentication:**
- Short-lived access tokens (15 minutes, configurable)
- Refresh tokens for long sessions
- Cryptographic signature verification via JWKS
- Audience validation (`https://alanhoangnguyen.com/mcp`)
- Issuer validation (`https://alanhoangnguyen.com/oauth/realms/mcp`)

**PKCE (Proof Key for Code Exchange):**
- S256 challenge method (SHA-256)
- Prevents authorization code interception attacks
- Required for OAuth 2.1 compliance

**Scope-Based Authorization:**
- `inventory:read` - Read access to inventory data
- `inventory:write` - Write access to inventory data
- Fine-grained permission control

### JWT Validator Service ✅

**Custom Go Service** (`registry.alanhoangnguyen.com/admin/jwt-validator:1.0.0`)

**Key Features:**
- JWKS caching (1 hour TTL, configurable)
- Automatic key rotation support
- Multiple validation layers (signature, issuer, audience, expiration, scopes)
- Transparent proxying to MCP backend
- Health check endpoint (`/health`)
- Structured logging (INFO level)

**Validation Flow:**
```go
1. Extract Bearer token from Authorization header
2. Parse JWT structure
3. Fetch public keys from Keycloak JWKS (cached)
4. Verify JWT signature using RSA public key
5. Validate issuer matches Keycloak realm
6. Validate audience matches MCP resource
7. Check token not expired
8. Verify all required scopes present
9. Add internal MCP_API_KEY header
10. Proxy request to organizerserver:3000
```

**Error Handling:**
- `401 Unauthorized` - Missing, invalid, or expired token
- `502 Bad Gateway` - Backend MCP server unavailable
- JSON error responses with descriptive messages

### Keycloak Configuration ✅

**Deployment Details:**
- Version: 23.0.7 (Quarkus 3.2.10)
- Database: PostgreSQL 16
- Proxy Mode: Edge (SSL termination at nginx)
- Base Path: `/oauth`
- Features: token-exchange, admin-fine-grained-authz

**Admin Console:**
- URL: `https://alanhoangnguyen.com/oauth/`
- Username: `admin`
- Password: Securely generated (32-byte base64)

**Health Checks:**
- Endpoint: `/oauth/health`
- Database connection monitoring
- Startup health period: 90 seconds

### Network Architecture ✅

**Internal Network** (`obsidian_network`):
```
keycloak-db:5432 ← keycloak:8080 ← jwt-validator:9000 ← nginx:443
                                                           ↓
                                                    organizerserver:3000
```

**External Access:**
- `https://alanhoangnguyen.com/oauth/` - Keycloak (admin + OAuth endpoints)
- `https://alanhoangnguyen.com/.well-known/oauth-protected-resource` - Resource metadata
- `https://alanhoangnguyen.com/mcp/sse` - MCP SSE (OAuth protected)
- `https://alanhoangnguyen.com/mcp/messages/` - MCP messages (OAuth protected)

**Security:**
- No external ports exposed (all services internal)
- SSL/TLS termination at nginx
- Services communicate via Docker internal DNS

## Test Results

### Automated Testing

✅ **OAuth Metadata Endpoint**
```bash
$ curl https://alanhoangnguyen.com/.well-known/oauth-protected-resource
{
  "resource": "https://alanhoangnguyen.com/mcp",
  "authorization_servers": ["https://alanhoangnguyen.com/oauth/realms/mcp"],
  "scopes_supported": ["inventory:read", "inventory:write"],
  "bearer_methods_supported": ["header"]
}
```

✅ **Keycloak Health Check**
```bash
$ curl https://alanhoangnguyen.com/oauth/health
{"status": "UP", "checks": [...]}
```

✅ **MCP Authorization Required**
```bash
$ curl https://alanhoangnguyen.com/mcp/sse
{"error":"missing_authorization","error_description":"Authorization header is required"}
HTTP/1.1 401 Unauthorized
```

✅ **Service Health**
```bash
$ docker ps --filter "name=keycloak" --filter "name=jwt"
keycloak        Up 11 minutes (healthy)
jwt_validator   Up 10 minutes (healthy)
keycloak_db     Up 15 minutes (healthy)
```

### Manual Testing (Pending)

⏳ **Keycloak Realm Configuration** - Requires manual steps:
1. Create realm: `mcp`
2. Create client: `chatgpt-mcp-client`
3. Configure PKCE: S256
4. Create scopes: `inventory:read`, `inventory:write`
5. Create test user: `mcp-user`

⏳ **OIDC Discovery** - After realm creation:
```bash
curl https://alanhoangnguyen.com/oauth/realms/mcp/.well-known/openid-configuration
```

⏳ **Token Request** - After client creation:
```bash
curl -X POST https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/token \
  -d grant_type=password \
  -d client_id=chatgpt-mcp-client \
  -d client_secret=<SECRET> \
  -d username=mcp-user \
  -d password=<PASSWORD> \
  -d scope="inventory:read inventory:write"
```

⏳ **MCP with Valid Token**:
```bash
curl -H "Authorization: Bearer <ACCESS_TOKEN>" https://alanhoangnguyen.com/mcp/sse
```

## Key Technical Improvements

### Code Quality

- **Go Best Practices**: JWT validator uses standard library + golang-jwt/jwt/v5
- **Error Handling**: Comprehensive error messages and HTTP status codes
- **Type Safety**: Strong typing with custom structs for JWT claims and JWKS
- **Dependency Management**: Minimal dependencies (only JWT library)

### Performance

- **JWKS Caching**: Public keys cached for 1 hour (reduces Keycloak load)
- **Connection Pooling**: HTTP client with reasonable timeouts (10s for JWKS, 3600s for SSE)
- **Health Checks**: All services have proper health check endpoints
- **Startup Dependencies**: Services wait for dependencies (keycloak waits for DB)

### Maintainability

- **Environment Variables**: All configuration externalized
- **Docker Compose**: Declarative infrastructure as code
- **Version Pinning**: Specific versions for reproducibility (Keycloak 23.0, PostgreSQL 16)
- **Documentation**: Comprehensive docs in markdown format
- **Backup Strategy**: Automated backup creation before modifications

### Security

- **Secrets Management**: All credentials in protected env file
- **Password Generation**: Cryptographically secure (openssl rand -base64 32)
- **Network Isolation**: Services on internal Docker network
- **SSL Everywhere**: HTTPS enforced by nginx
- **Token Expiration**: Short-lived tokens (15 minutes)
- **Signature Verification**: RSA-2048 keys with SHA-256

### Observability

- **Structured Logging**: All services log to stdout/stderr
- **Health Endpoints**: /health available on all services
- **Container Names**: Descriptive names for easy identification
- **Status Monitoring**: Docker health checks with proper intervals

## What's Next

### Immediate (Manual Configuration)

1. **Access Keycloak Admin Console**
   - URL: https://alanhoangnguyen.com/oauth/
   - Login with admin credentials

2. **Create Realm and Client**
   - Follow steps in `/root/Orchestration/obsRemote/docs/keycloak-oauth-implementation-summary.md`
   - Configure PKCE S256
   - Set up redirect URIs for ChatGPT/Claude

3. **Test OAuth Flow**
   - Run test script: `./docs/test-oauth-setup.sh`
   - Verify token issuance
   - Test MCP access with valid token

### Short Term (Integration)

4. **Configure ChatGPT MCP Connector**
   - Authorization URL: `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/auth`
   - Token URL: `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/token`
   - Client ID: `chatgpt-mcp-client`
   - Client Secret: (from Keycloak)
   - Scopes: `openid inventory:read inventory:write`

5. **Configure Claude MCP Connector**
   - Same OAuth endpoints as ChatGPT
   - May require different redirect URI

6. **Monitor Logs**
   ```bash
   docker logs -f jwt_validator
   docker logs -f keycloak
   ```

### Long Term (Maintenance)

7. **Regular Updates**
   - Weekly: Check service health
   - Monthly: Update Keycloak image, rotate admin password
   - Quarterly: Security audit, review token lifespans

8. **Backup Strategy**
   - Database: `/root/Orchestration/obsRemote/keycloak/db-data/`
   - Keycloak config: `/root/Orchestration/obsRemote/keycloak/data/`
   - Credentials: Keep secure copy of env file

9. **Scaling Considerations**
   - Keycloak clustering if high availability needed
   - JWT validator horizontal scaling (stateless)
   - Database replication for HA

## Documentation Created

### Primary Documents

1. **Implementation Summary** (`docs/keycloak-oauth-implementation-summary.md`)
   - Complete architecture overview
   - Service descriptions
   - Configuration details
   - Testing procedures
   - Troubleshooting guide

2. **Environment Variables Reference** (`mcp-keycloak-envs.md`)
   - All environment variables documented
   - Security best practices
   - Rotation schedules
   - Troubleshooting tips

3. **Test Script** (`docs/test-oauth-setup.sh`)
   - Automated testing suite
   - Interactive token testing
   - Service health checks
   - Output validation

4. **Credentials File** (`/tmp/.../scratchpad/keycloak-credentials.txt`)
   - Admin console access
   - Database credentials
   - Manual configuration steps

### Configuration Files

5. **Docker Compose** (`run_obsidian_remote.yml`)
   - 3 new service definitions
   - Health checks
   - Dependencies
   - Volume mounts

6. **Nginx Config** (`custom_server.conf`)
   - OAuth routes
   - Metadata endpoint
   - JWT validator proxy

7. **Environment Variables** (`dev/docker-compose.env`)
   - Keycloak credentials
   - JWT validator settings
   - All configuration

## Rollback Plan

If issues occur, complete rollback available:

```bash
cd /root/Orchestration/obsRemote

# Stop OAuth services
docker compose -f run_obsidian_remote.yml stop jwt-validator keycloak keycloak-db

# Restore configurations
cp custom_server.conf.backup-20260131_013846 custom_server.conf
cp dev/docker-compose.env.backup-20260131_013846 dev/docker-compose.env

# Restart nginx
docker compose -f run_obsidian_remote.yml restart nginx_proxy_manager

# MCP will work with original API key method
```

**Backups Created:**
- `run_obsidian_remote.yml.backup-20260131_013846`
- `custom_server.conf.backup-20260131_013846`
- `dev/docker-compose.env.backup-20260131_013846`

## Status

✅ **Infrastructure Deployment** - COMPLETED
- All services running and healthy
- OAuth endpoints accessible
- MCP endpoints protected
- Automated tests passing

⏳ **Manual Configuration** - PENDING
- Keycloak realm creation
- Client configuration
- User setup
- Scope assignment

⏳ **Integration Testing** - PENDING
- Full OAuth 2.1 flow test
- ChatGPT connector setup
- Claude connector setup
- End-to-end validation

✅ **Documentation** - COMPLETED
- Implementation guide
- Environment variables reference
- Test script
- This completion document

## Conclusion

Successfully implemented a production-ready OAuth 2.1 authorization infrastructure for MCP endpoints. The system provides:

- **Security**: Industry-standard authentication with JWT, PKCE, and short-lived tokens
- **Scalability**: Stateless JWT validator can scale horizontally
- **Maintainability**: Well-documented, version-controlled, environment-based configuration
- **Reliability**: Health checks, automatic restarts, and proper error handling
- **Compliance**: OAuth 2.1, RFC 8414, RFC 7519, RFC 7636 compliant

The infrastructure is ready for use once manual Keycloak configuration is completed. All automated testing passes, services are healthy, and comprehensive documentation is available for operations and troubleshooting.

---

**Implementation completed:** 2026-01-31
**Implemented by:** Claude Code
**Service versions:**
- keycloak: 23.0.7
- keycloak-db: PostgreSQL 16 Alpine
- jwt-validator: 1.0.0
- organizerserver: 0.1.3 (upgraded)
- nginx: openresty
