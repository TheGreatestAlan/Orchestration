# MCP-Keycloak Environment Variables Documentation

## Overview

This document describes all environment variables used in the Keycloak OAuth 2.1 implementation for MCP (Model Context Protocol) endpoints.

**Location:** `/root/Orchestration/obsRemote/dev/docker-compose.env`

---

## Keycloak Environment Variables

### KEYCLOAK_ADMIN
- **Service:** keycloak
- **Type:** String
- **Required:** Yes
- **Current Value:** `admin`
- **Description:** Username for the Keycloak admin console
- **Usage:** Login to https://alanhoangnguyen.com/oauth/

### KEYCLOAK_ADMIN_PASSWORD
- **Service:** keycloak
- **Type:** String (Base64 encoded)
- **Required:** Yes
- **Current Value:** `uDiGhYwhDvgNbp/h2x2V+F2QvEBw/9kLkbtjooBOMrE=`
- **Description:** Password for the Keycloak admin user
- **Security:** Generated with `openssl rand -base64 32`
- **Rotation:** Recommended quarterly

---

## Keycloak Database Environment Variables

### KEYCLOAK_DB_PASSWORD
- **Service:** keycloak, keycloak-db
- **Type:** String (Base64 encoded)
- **Required:** Yes
- **Current Value:** `SVurSptgncxFD9FCBwoh4JTXfxupZVB8ceIJhDFMiHY=`
- **Description:** Password for PostgreSQL database user `keycloak`
- **Database:** PostgreSQL 16
- **Security:** Generated with `openssl rand -base64 32`
- **Rotation:** Recommended quarterly

### PostgreSQL Database (Fixed Values)
- **Database Name:** `keycloak` (hardcoded in compose)
- **Database User:** `keycloak` (hardcoded in compose)
- **Port:** 5432 (internal only)

---

## JWT Validator Environment Variables

### JWT_VALIDATOR_PORT
- **Service:** jwt-validator
- **Type:** Integer
- **Required:** Yes
- **Current Value:** `9000`
- **Description:** Internal port where JWT validator listens
- **Network:** obsidian_network (internal only, not exposed to host)

### JWT_VALIDATOR_VERSION
- **Service:** jwt-validator
- **Type:** String (semver)
- **Required:** No (defaults to `latest`)
- **Current Value:** `1.0.0`
- **Description:** Docker image tag for jwt-validator
- **Image:** `registry.alanhoangnguyen.com/admin/jwt-validator:${JWT_VALIDATOR_VERSION}`

### JWKS_CACHE_TTL_SECONDS
- **Service:** jwt-validator
- **Type:** Integer
- **Required:** No
- **Current Value:** `3600` (1 hour)
- **Description:** How long to cache Keycloak's public keys (JWKS) before refreshing
- **Recommendation:** 3600 (1 hour) for production, lower for testing

### JWT_VALIDATION_LOG_LEVEL
- **Service:** jwt-validator
- **Type:** Enum (DEBUG, INFO, WARN, ERROR)
- **Required:** No
- **Current Value:** `INFO`
- **Description:** Log level for JWT validator service
- **Options:**
  - `DEBUG` - Verbose logging (development only)
  - `INFO` - Standard logging (recommended for production)
  - `WARN` - Warnings and errors only
  - `ERROR` - Errors only

---

## MCP Environment Variables (Existing)

### MCP_API_KEY
- **Service:** organizerserver, jwt-validator
- **Type:** String (Base64 encoded)
- **Required:** Yes
- **Current Value:** `Eq/zlM20kVDlyWWarASkHC3q1KfmpIyptprMV5MgWrg=`
- **Description:** API key for internal authentication to MCP backend
- **Usage:** JWT validator adds this as `Authorization: Bearer ${MCP_API_KEY}` when proxying to organizerserver
- **Note:** This is still used internally after OAuth validation

### MCP_DNS_REBINDING_PROTECTION
- **Service:** organizerserver
- **Type:** Boolean
- **Required:** No
- **Current Value:** `true`
- **Description:** Enable DNS rebinding protection for production
- **Recommendation:** Keep as `true` in production

### MCP_ALLOWED_HOSTS
- **Service:** organizerserver
- **Type:** Comma-separated strings
- **Required:** Yes (if DNS_REBINDING_PROTECTION=true)
- **Current Value:** `alanhoangnguyen.com,www.alanhoangnguyen.com`
- **Description:** Allowed host headers for MCP requests
- **Note:** Must match domains serving MCP

### MCP_ALLOWED_ORIGINS
- **Service:** organizerserver
- **Type:** Comma-separated URLs
- **Required:** Yes (for CORS)
- **Current Value:** `https://alanhoangnguyen.com,https://www.alanhoangnguyen.com`
- **Description:** Allowed CORS origins for MCP requests
- **Note:** Must include https:// prefix

---

## JWT Validator Internal Environment Variables

These are set internally by the jwt-validator service based on the above variables:

### PORT
- **Derived from:** JWT_VALIDATOR_PORT
- **Default:** 9000
- **Usage:** HTTP server listen port

### KEYCLOAK_ISSUER
- **Hardcoded:** `https://alanhoangnguyen.com/oauth/realms/mcp`
- **Description:** Expected JWT issuer (iss claim)
- **Validation:** JWT must have this exact issuer

### KEYCLOAK_JWKS_URI
- **Hardcoded:** `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs`
- **Description:** URL to fetch Keycloak's public keys (JWKS)
- **Caching:** Cached for JWKS_CACHE_TTL_SECONDS

### MCP_BACKEND_URL
- **Hardcoded:** `http://organizerserver:3000`
- **Description:** Internal URL of MCP server to proxy validated requests to
- **Network:** Uses Docker internal DNS

### EXPECTED_AUDIENCE
- **Hardcoded:** `https://alanhoangnguyen.com/mcp`
- **Description:** Expected JWT audience (aud claim)
- **Validation:** JWT must have this exact audience

### REQUIRED_SCOPES
- **Hardcoded:** `inventory:read,inventory:write`
- **Description:** Comma-separated list of required OAuth scopes
- **Validation:** JWT must contain ALL these scopes in the scope claim

### JWKS_CACHE_TTL
- **Derived from:** JWKS_CACHE_TTL_SECONDS (converted to Duration)
- **Default:** 3600 seconds (1 hour)
- **Usage:** Internal cache expiration

### LOG_LEVEL
- **Derived from:** JWT_VALIDATION_LOG_LEVEL
- **Default:** INFO
- **Usage:** Go logger level

---

## Keycloak Service Configuration (Environment Variables)

These are used by the Keycloak container:

### KC_HOSTNAME
- **Value:** `alanhoangnguyen.com`
- **Description:** Public hostname for Keycloak
- **Usage:** Used in generated URLs, tokens, OIDC discovery

### KC_PROXY
- **Value:** `edge`
- **Description:** Keycloak is behind an edge proxy (nginx)
- **Effect:** Trusts X-Forwarded-* headers

### KC_HTTP_ENABLED
- **Value:** `true`
- **Description:** Enable HTTP listener (internal only)
- **Port:** 8080 (internal)

### KC_HOSTNAME_STRICT
- **Value:** `true`
- **Description:** Enforce strict hostname checking
- **Security:** Prevents hostname spoofing

### KC_HOSTNAME_STRICT_HTTPS
- **Value:** `false`
- **Description:** Don't enforce HTTPS at Keycloak level (nginx handles SSL)
- **Note:** SSL termination happens at nginx

### KC_HTTP_RELATIVE_PATH
- **Value:** `/oauth`
- **Description:** Base path for Keycloak URLs
- **Result:** Keycloak serves from /oauth/* instead of root

### KC_DB
- **Value:** `postgres`
- **Description:** Database type

### KC_DB_URL_HOST
- **Value:** `keycloak-db`
- **Description:** Database hostname (Docker service name)

### KC_DB_URL_PORT
- **Value:** `5432`
- **Description:** PostgreSQL port

### KC_DB_URL_DATABASE
- **Value:** `keycloak`
- **Description:** Database name

### KC_DB_USERNAME
- **Value:** `keycloak`
- **Description:** Database username

### KC_DB_PASSWORD
- **Value:** `${KEYCLOAK_DB_PASSWORD}`
- **Description:** Database password (from env file)

### KC_HEALTH_ENABLED
- **Value:** `true`
- **Description:** Enable health check endpoints
- **Endpoint:** /oauth/health

### KC_METRICS_ENABLED
- **Value:** `true`
- **Description:** Enable metrics endpoints
- **Endpoint:** /oauth/metrics

---

## Environment Variable Best Practices

### Security

1. **Never commit sensitive values to git**
   - Keep `dev/docker-compose.env` in .gitignore
   - Use environment-specific files (dev, staging, prod)

2. **Rotate credentials regularly**
   - Admin password: Quarterly
   - Database password: Quarterly
   - MCP_API_KEY: As needed (requires service restart)

3. **Use strong passwords**
   - Generate with: `openssl rand -base64 32`
   - Minimum 32 characters
   - Mix of uppercase, lowercase, numbers, special characters

### Configuration Management

1. **Backup before changes**
   ```bash
   cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)
   ```

2. **Validate after changes**
   ```bash
   source script/sourceEnv.sh
   docker compose -f run_obsidian_remote.yml config > /dev/null
   ```

3. **Restart affected services**
   ```bash
   docker compose -f run_obsidian_remote.yml restart jwt-validator keycloak
   ```

### Monitoring

1. **Check service health**
   ```bash
   docker ps --filter "name=keycloak"
   docker ps --filter "name=jwt"
   ```

2. **View service logs**
   ```bash
   docker logs jwt_validator
   docker logs keycloak
   docker logs keycloak_db
   ```

3. **Test endpoints**
   ```bash
   curl https://alanhoangnguyen.com/oauth/health
   curl https://alanhoangnguyen.com/.well-known/oauth-protected-resource
   ```

---

## Troubleshooting Environment Variables

### Issue: Services won't start

**Check:**
1. Environment file is sourced: `source script/sourceEnv.sh`
2. All required variables are set: `echo $KEYCLOAK_ADMIN_PASSWORD`
3. No syntax errors in env file: `cat dev/docker-compose.env | grep -v "^#" | grep "="`

### Issue: Keycloak database connection fails

**Check:**
1. KEYCLOAK_DB_PASSWORD matches in both services
2. Database service is healthy: `docker ps --filter "name=keycloak_db"`
3. Database logs: `docker logs keycloak_db`

### Issue: JWT validation fails

**Check:**
1. JWT_VALIDATOR_PORT matches in nginx config
2. KEYCLOAK_ISSUER matches realm URL
3. EXPECTED_AUDIENCE matches token audience
4. REQUIRED_SCOPES match client scopes

### Issue: Variables not being picked up

**Solution:**
1. Restart services: `docker compose -f run_obsidian_remote.yml restart <service>`
2. Or recreate: `docker compose -f run_obsidian_remote.yml up -d --force-recreate <service>`

---

## Environment Variable Reference Table

| Variable | Service | Type | Required | Default | Description |
|----------|---------|------|----------|---------|-------------|
| KEYCLOAK_ADMIN | keycloak | String | Yes | - | Admin username |
| KEYCLOAK_ADMIN_PASSWORD | keycloak | String | Yes | - | Admin password |
| KEYCLOAK_DB_PASSWORD | keycloak, keycloak-db | String | Yes | - | Database password |
| JWT_VALIDATOR_PORT | jwt-validator | Integer | Yes | - | Service port |
| JWT_VALIDATOR_VERSION | jwt-validator | String | No | latest | Image version |
| JWKS_CACHE_TTL_SECONDS | jwt-validator | Integer | No | 3600 | JWKS cache TTL |
| JWT_VALIDATION_LOG_LEVEL | jwt-validator | String | No | INFO | Log level |
| MCP_API_KEY | organizerserver, jwt-validator | String | Yes | - | Internal API key |
| MCP_DNS_REBINDING_PROTECTION | organizerserver | Boolean | No | true | DNS protection |
| MCP_ALLOWED_HOSTS | organizerserver | String | Yes | - | Allowed hosts |
| MCP_ALLOWED_ORIGINS | organizerserver | String | Yes | - | Allowed CORS origins |

---

## Adding New Environment Variables

### 1. Add to docker-compose.env

```bash
cd /root/Orchestration/obsRemote
nano dev/docker-compose.env
```

Add at the end of Keycloak OAuth section:
```bash
NEW_VARIABLE=value
```

### 2. Update docker compose file

```yaml
jwt-validator:
  environment:
    - NEW_VARIABLE=${NEW_VARIABLE}
```

### 3. Validate and restart

```bash
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml config > /dev/null
docker compose -f run_obsidian_remote.yml up -d --force-recreate jwt-validator
```

### 4. Document here

Update this file with the new variable details.

---

## Related Documentation

- **Main Implementation Guide:** `/root/Orchestration/obsRemote/docs/keycloak-oauth-implementation-summary.md`
- **Test Script:** `/root/Orchestration/obsRemote/docs/test-oauth-setup.sh`
- **Docker Compose:** `/root/Orchestration/obsRemote/run_obsidian_remote.yml`
- **Nginx Config:** `/root/Orchestration/obsRemote/custom_server.conf`

---

**Last Updated:** 2026-01-31
**Version:** 1.0.0
