# obsRemote Production System

A small, scrappy Docker Compose-based production system hosting multiple microservices for AI agents, workflow automation, private registries, OAuth authentication, and VPN access.

## Architecture Overview

This system runs 17 containerized services orchestrated via Docker Compose:

### Core AI Services
- **organizerserver** - Manages git repositories and physical inventory
  - MCP server with inventory tools (7 tools)
  - Streamable HTTP transport on port 3000
  - OAuth 2.1 protected via jwt-validator
- **mcp-obsidian** - Obsidian vault access for Claude/ChatGPT
  - MCP server with vault tools (9 tools: search, read/write, tags, MOCs)
  - Streamable HTTP transport on port 3000
  - Read-only vault access, OAuth 2.1 protected
- **updater** - Synchronizes Obsidian vault locations with credentials
- **agent-server** - Main AI agent server with multi-model LLM support (Fireworks, OpenAI)
  - REST API and WebSocket support
  - Firebase authentication
  - Scheduler integration
  - User encryption and data persistence
- **translator** - Translation service powered by Fireworks AI
- **open-webui** - Web interface for LLM interaction (points to translator service)

### Infrastructure Services
- **nginx_proxy_manager** - Reverse proxy with SSL termination
  - Routes traffic to all services
  - Manages Let's Encrypt certificates
  - HTTP → HTTPS redirect
- **certbot** - Automated SSL certificate renewal (runs every 12 hours)
- **wireguard** - VPN server for secure remote access
- **scheduler** - Task scheduling and automation service
- **n8n** - Workflow automation platform

### Registry Services
- **docker-registry** - Private Docker image registry
  - Registry UI available at registry.alanhoangnguyen.com
  - Basic auth protected
- **pypi-server** - Private Python package repository
  - Available at helper.alanhoangnguyen.com/pypi/

### Security Services
- **vaultwarden** - Self-hosted password manager (Bitwarden-compatible)
  - Available at vault.alanhoangnguyen.com
  - End-to-end encrypted password vault
  - Supports browser extensions, mobile apps, and desktop clients
  - Admin panel protected with secure token
  - Automated daily backups with 30-day retention

### OAuth Authentication Services
- **keycloak** - OAuth 2.1 authorization server (Keycloak 23.0)
  - Admin console at https://alanhoangnguyen.com/oauth/
  - Provides OAuth 2.1 + PKCE authentication for MCP endpoints
  - OIDC discovery, JWKS public key distribution
  - Token issuance and management
- **keycloak-db** - PostgreSQL 16 database for Keycloak
  - Stores realm configurations, clients, users
  - Persistent storage for OAuth data
- **jwt-validator** - Custom JWT validation service (Go)
  - Validates JWT tokens from Keycloak
  - Verifies signatures, issuer, audience, expiration, scopes
  - Transparent proxy to MCP backend
  - JWKS caching for performance

## Directory Structure

```
obsRemote/
├── run_obsidian_remote.yml    # Main Docker Compose file
├── custom_server.conf          # Nginx reverse proxy configuration
├── script/                     # Management scripts
│   ├── setEnvAndRun.sh        # Source env and start services
│   ├── sourceEnv.sh           # Source environment variables
│   ├── run.sh                 # Simple docker compose up
│   ├── down.sh                # Stop all services
│   ├── pullNewImages.sh       # Update all Docker images
│   ├── see-logs.sh            # View service logs
│   ├── shell-into.sh          # Shell into containers
│   └── docker-compose.env     # Example/template only (6 lines)
├── dev/                        # Development/config files (THIS is where env lives)
│   ├── docker-compose.env     # **ACTUAL environment variables** (sourced by all scripts)
│   ├── .htpasswd              # Basic auth credentials
│   └── open-webui/            # Open WebUI data
├── agent-server/
│   ├── logs/                  # Agent server logs
│   ├── user/                  # User data persistence
│   └── firebase/              # Firebase credentials
├── certbot-scripts/
│   └── renew-certs.sh         # Certificate renewal script
├── npm/                        # Nginx Proxy Manager data
│   ├── data/
│   ├── letsencrypt/           # SSL certificates
│   └── log/
├── registry/                   # Docker registry storage
│   ├── data/
│   └── auth/
├── scheduler_data/            # Scheduler task persistence
├── n8n_data/                  # n8n workflow data
├── wireguard-config/          # WireGuard VPN configs
├── vaultwarden/               # Vaultwarden password manager data
│   ├── vw-data/               # Encrypted vault database
│   ├── backup-vaultwarden.sh  # Automated backup script
│   └── RESTORE.md             # Restore procedures
├── keycloak/                  # Keycloak OAuth server data
│   ├── db-data/               # PostgreSQL database storage
│   └── data/                  # Keycloak configuration and cache
├── docs/                      # Documentation
│   ├── keycloak-oauth-implementation-summary.md
│   ├── test-oauth-setup.sh    # OAuth testing script
│   └── task-log/              # Task completion logs
├── mcp-keycloak-envs.md       # OAuth environment variables reference
└── webroot/                   # Certbot webroot for challenges
```

## Environment Setup

**CRITICAL**: All services require environment variables defined in `dev/docker-compose.env` (NOT `script/docker-compose.env` which is just a template). This file contains:

- **Git credentials** - For Obsidian vault syncing
- **API keys** - Fireworks AI, OpenAI, MCP
- **Service ports** - REST, WebSocket endpoints
- **Domain configuration** - Multiple domains served
- **SSL email** - For Let's Encrypt notifications
- **Encryption keys** - User data encryption
- **Auth credentials** - n8n, registry, PyPI
- **OAuth credentials** - Keycloak admin, database passwords
- **JWT validator config** - Port, version, cache TTL, log level

See `mcp-keycloak-envs.md` for detailed OAuth environment variable documentation.

**IMPORTANT**: Always source the environment before running docker-compose commands:
```bash
source script/sourceEnv.sh
```

Or use the wrapper scripts which do this automatically.

## Common Operations

### Starting Services

**Recommended (with env sourcing and image pull):**
```bash
cd obsRemote
./script/setEnvAndRun.sh
```

**Quick start (assumes env already sourced):**
```bash
cd obsRemote
./script/run.sh
```

**Manual (requires sourcing env first):**
```bash
cd obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d
```

### Stopping Services

```bash
cd obsRemote
./script/down.sh
```

This stops and removes all containers and volumes.

### Updating Images

```bash
cd obsRemote
./script/pullNewImages.sh
```

This script:
1. Compares local and remote image digests
2. Pulls only updated images
3. Cleans up old images

### Viewing Logs

```bash
cd obsRemote
./script/see-logs.sh <service-name>          # View logs
./script/see-logs.sh -t <service-name>       # Tail logs (follow mode)
```

Example:
```bash
./script/see-logs.sh agent-server
./script/see-logs.sh -t nginx_proxy_manager
```

### Shell into Container

```bash
cd obsRemote
./script/shell-into.sh <service-name> [shell]
```

Example:
```bash
./script/shell-into.sh agent-server bash
./script/shell-into.sh nginx_proxy_manager sh
```

## Service Endpoints

All services are proxied through nginx on standard ports:

- **Port 80** - HTTP (redirects to HTTPS)
- **Port 443** - HTTPS
- **Port 81** - Nginx Proxy Manager admin UI
- **Port 51820/udp** - WireGuard VPN
- **Port 12346** - Agent Server WebSocket (localhost only)

### Domains Served

- alanhoangnguyen.com
- www.alanhoangnguyen.com
- openwebui.alanhoangnguyen.com - Open WebUI interface
- helper.alanhoangnguyen.com - PyPI server
- n8n.alanhoangnguyen.com - n8n workflow automation
- registry.alanhoangnguyen.com - Docker registry
- vault.alanhoangnguyen.com - Vaultwarden password manager
- flofluent.com
- www.flofluent.com

### OAuth Endpoints

**OAuth 2.1 / OIDC:**
- `https://alanhoangnguyen.com/oauth/` - Keycloak admin console
- `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/auth` - Authorization endpoint
- `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/token` - Token endpoint
- `https://alanhoangnguyen.com/oauth/realms/mcp/.well-known/openid-configuration` - OIDC discovery
- `https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs` - JWKS public keys
- `https://alanhoangnguyen.com/.well-known/oauth-protected-resource` - OAuth resource metadata (RFC 8414)
- `https://alanhoangnguyen.com/.well-known/oauth-authorization-server` - OAuth discovery (for Claude)

## MCP Server Infrastructure

The system hosts multiple MCP (Model Context Protocol) servers behind a single OAuth-protected domain. All servers share the same authentication, making it easy to add new capabilities.

### Architecture

```
Claude Desktop/Web
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  alanhoangnguyen.com (Nginx)                                 │
│  ├── /.well-known/oauth-authorization-server (shared)        │
│  ├── /mcp            → jwt-validator:9000/mcp                │
│  └── /mcp/obsidian   → jwt-validator:9000/mcp/obsidian       │
└──────────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│  JWT Validator (jwt_validator:9000)                          │
│  ├── Validates OAuth token against Keycloak JWKS             │
│  ├── /mcp          → organizerserver:3000/mcp                │
│  └── /mcp/obsidian → mcp-obsidian:3000/mcp                   │
└──────────────────────────────────────────────────────────────┘
        │                           │
        ▼                           ▼
┌─────────────────────┐   ┌─────────────────────┐
│  organizerserver    │   │  mcp-obsidian       │
│  :3000/mcp          │   │  :3000/mcp          │
│  Inventory tools    │   │  Obsidian vault     │
└─────────────────────┘   └─────────────────────┘
```

### Deployed MCP Servers

| Server | URL | Purpose | Tools |
|--------|-----|---------|-------|
| Inventory | `https://alanhoangnguyen.com/mcp` | Physical item tracking | 7 tools (get/create/delete items, find locations) |
| Obsidian | `https://alanhoangnguyen.com/mcp/obsidian` | Obsidian vault access | 9 tools (search, read/write notes, tags, MOCs) |

### MCP Authentication (Shared)

All MCP servers share the same OAuth credentials:

| Field | Value |
|-------|-------|
| Discovery URL | `https://alanhoangnguyen.com/.well-known/oauth-authorization-server` |
| Client ID | `chatgpt-mcp-client` |
| Client Secret | See `dev/docker-compose.env` |
| Test User | `mcp-oauth-test` / `McpTest2026` |

### Adding New MCP Servers

To add a new MCP server (e.g., `/mcp/calendar`):

**1. Update JWT Validator** (`jwt-validator/main.go`):
```go
// Add to Config struct
MCPBackendCalendarURL string

// Add to loadConfig()
MCPBackendCalendarURL: getEnv("MCP_BACKEND_CALENDAR_URL", "http://mcp-calendar:3000"),

// Add route in main()
mux.Handle("/mcp/calendar", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))

// Add to getBackendURL()
if strings.HasPrefix(path, "/mcp/calendar") {
    return v.config.MCPBackendCalendarURL + "/mcp"
}
```

**2. Add Nginx Location** (`custom_server.conf`):
```nginx
location = /mcp/calendar {
    auth_basic off;
    proxy_pass http://jwt-validator:9000/mcp/calendar;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header Authorization $http_authorization;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, Accept, Mcp-Session-Id" always;
    add_header Access-Control-Expose-Headers "Mcp-Session-Id" always;
    if ($request_method = 'OPTIONS') { return 204; }
}
```

**3. Add Docker Service** (`run_obsidian_remote.yml`):
```yaml
mcp-calendar:
  image: registry.alanhoangnguyen.com/admin/mcp-calendar:${MCP_CALENDAR_VERSION:-latest}
  container_name: mcp-calendar
  restart: unless-stopped
  command: ["node", "src/index.js", "/data"]
  environment:
    - PORT=3000
    - MCP_API_KEY=${MCP_API_KEY}
  volumes:
    - ./calendar-data:/data:ro
  networks:
    - obsidian_network
```

**4. Add JWT Validator Env Var**:
```yaml
jwt-validator:
  environment:
    - MCP_BACKEND_CALENDAR_URL=http://mcp-calendar:3000
```

**5. Deploy**:
```bash
# Bump JWT validator version, rebuild, push
cd jwt-validator
docker build -t registry.../jwt-validator:X.Y.Z .
docker push registry.../jwt-validator:X.Y.Z

# Update version in docker-compose.env
# JWT_VALIDATOR_VERSION=X.Y.Z
# MCP_CALENDAR_VERSION=1.0.0

# Deploy
cd obsRemote && source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml pull
docker compose -f run_obsidian_remote.yml up -d --force-recreate jwt-validator mcp-calendar
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload
```

### MCP Server Requirements

New MCP servers must:
- Implement MCP Streamable HTTP transport (single `/mcp` endpoint)
- Return `mcp-session-id` header for session management
- Close connections after sending responses (not keep-alive SSE)
- Accept `Authorization: Bearer` header (passed through by JWT validator)
- Listen on port 3000 (configurable)

### Testing MCP Endpoints

```bash
# Get OAuth token
TOKEN=$(curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=chatgpt-mcp-client" \
  -d "client_secret=YOUR_SECRET" \
  -d "username=mcp-oauth-test" \
  -d "password=McpTest2026" \
  -d "scope=openid email profile" | jq -r '.access_token')

# Test initialize
curl -X POST "https://alanhoangnguyen.com/mcp/obsidian" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## SSL Certificates

**All SSL certificates are managed automatically by the certbot container** - no manual intervention needed!

### How It Works

The certbot container obtains and renews Let's Encrypt certificates, which are automatically available to nginx through a shared Docker volume:

- **Certbot writes**: `./npm/letsencrypt` (host) → `/etc/letsencrypt` (certbot container)
- **Nginx reads**: `./npm/letsencrypt` (host) → `/etc/letsencrypt` (nginx container)
- **Same files**: Both containers access the exact same certificates via the shared volume

### Automatic Renewal

- Certbot container runs renewal check every 12 hours
- Uses HTTP-01 challenge via webroot method (`./webroot` → `/var/www/certbot`)
- Renewal script: `certbot-scripts/renew-certs.sh`
- Certificates stored at: `npm/letsencrypt/live/<domain>/`

### Manual Certificate Request

If you need to add a new domain:

1. Add domain to `CERTBOT_DOMAINS` in `dev/docker-compose.env`
2. Ensure DNS points to your server
3. Run:
   ```bash
   source script/sourceEnv.sh
   docker compose -f run_obsidian_remote.yml exec certbot certbot certonly \
     --webroot --webroot-path=/var/www/certbot \
     --email $CERTBOT_EMAIL --agree-tos --non-interactive -d newdomain.com
   ```
4. Update `custom_server.conf` with nginx configuration
5. Reload nginx:
   ```bash
   source script/sourceEnv.sh
   docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload
   ```

## Network

All services communicate via the `obsidian_network` bridge network, enabling service-to-service communication by container name.

## Data Persistence

Key data is persisted via Docker volumes:
- Agent server: `agent-server/logs`, `agent-server/user`
- Nginx: `npm/data`, `npm/letsencrypt`, `npm/log`
- Registry: `registry/data`
- n8n: `n8n_data/`
- Scheduler: `scheduler_data/`
- WireGuard: `wireguard-config/`
- Vaultwarden: `vaultwarden/vw-data/` (automated daily backups to `/var/backups/vaultwarden/`)
- Keycloak: `keycloak/db-data/`, `keycloak/data/` (OAuth configurations, users, clients)

## Maintenance

### Backups

The system creates automatic backups with timestamps:
- `run_obsidian_remote.yml.*` - Docker Compose backups
- `custom_server.conf.*` - Nginx config backups
- Vaultwarden vault data - Automated daily backups at 2:00 AM
  - Location: `/var/backups/vaultwarden/`
  - Retention: 30 days
  - Manual backup: `./vaultwarden/backup-vaultwarden.sh`
  - Restore guide: `./vaultwarden/RESTORE.md`
  - Logs: `/var/log/vaultwarden-backup.log`

Check the `.gitignore` to see what's excluded from version control.

### Logs

Agent server logs are available at:
- `agent-server/logs/llm.log` - LLM interaction logs
- `agent-server/logs/general.log` - General application logs

Nginx logs: `npm/log/`

### Automated Cleanup

The system automatically cleans up unused Docker resources to prevent disk space issues:

**Automated cleanup (via cron):**
- Runs weekly on Sunday at 2 AM
- Removes dangling/untagged images
- Removes unused images older than 7 days
- Runs Docker registry garbage collection
- Logs to `/var/log/docker-cleanup.log`

**Manual cleanup:**
```bash
cd obsRemote
./script/cleanup-docker.sh
```

**View cleanup logs:**
```bash
tail -f /var/log/docker-cleanup.log
```

**Change cleanup schedule:**
```bash
crontab -e
# Default: 0 2 * * 0 (weekly)
# Daily:   0 2 * * * (every day at 2 AM)
```

## Security Notes

- Registry and PyPI require HTTP basic authentication
- User data encrypted with `USER_ENCRYPTION_KEY`
- Firebase service account key required for agent-server
- WireGuard provides secure VPN access
- All HTTP traffic redirected to HTTPS
- Agent server WebSocket only bound to localhost

### OAuth 2.1 Security

- **MCP endpoints protected** - Require valid JWT access tokens from Keycloak
- **PKCE required** - S256 challenge method prevents authorization code interception
- **Short-lived tokens** - Access tokens expire in 15 minutes (configurable)
- **Signature verification** - JWT validated using RSA public keys from JWKS
- **Scope validation** - Tokens must contain required scopes (inventory:read, inventory:write)
- **Audience validation** - Tokens must be issued for `https://alanhoangnguyen.com/mcp`
- **Network isolation** - OAuth services on internal Docker network, no external ports
- **Credential rotation** - Admin password and database password should be rotated quarterly

## Troubleshooting

**Services won't start:**
- Ensure `dev/docker-compose.env` exists with all required variables
- Source the environment: `source script/sourceEnv.sh`
- Check Docker daemon is running

**SSL certificate issues:**
- Check certbot logs: `./script/see-logs.sh certbot`
- Verify `webroot/` is accessible
- Ensure DNS points to server

**Network connectivity:**
- All services must be on `obsidian_network`
- Check nginx routing in `custom_server.conf`
- Verify firewall allows ports 80, 443, 51820

**Image updates failing:**
- Check Docker Hub connectivity
- Verify registry credentials if using private images
- Try `docker pull` manually

### OAuth Troubleshooting

**Keycloak won't start:**
- Check database is healthy: `docker ps --filter "name=keycloak_db"`
- Check database logs: `./script/see-logs.sh keycloak-db`
- Verify KEYCLOAK_DB_PASSWORD matches in both services
- Allow 90 seconds startup time for health check

**JWT validation failing (401 errors):**
- Verify realm "mcp" exists in Keycloak admin console
- Check JWKS endpoint: `curl https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs`
- Check jwt-validator logs: `./script/see-logs.sh jwt_validator`
- Verify token issuer matches: `https://alanhoangnguyen.com/oauth/realms/mcp`
- Check token hasn't expired (15 minute default)
- Verify required scopes present in token

**MCP endpoints returning 401:**
- Test without OAuth: Stop jwt-validator and update nginx to proxy directly to organizerserver
- Check if token is being sent: Look for `Authorization: Bearer` header
- Verify jwt-validator is running: `docker ps --filter "name=jwt"`
- Test OAuth metadata: `curl https://alanhoangnguyen.com/.well-known/oauth-protected-resource`

**JWKS cache issues:**
- Restart jwt-validator: `docker compose -f run_obsidian_remote.yml restart jwt-validator`
- Check cache TTL in environment: `echo $JWKS_CACHE_TTL_SECONDS` (default 3600s)
- Verify Keycloak JWKS endpoint accessible from jwt-validator container

**Testing OAuth setup:**
Run the automated test suite:
```bash
cd /root/Orchestration/obsRemote
./docs/test-oauth-setup.sh
```

**Rollback OAuth implementation:**
If OAuth is causing issues, you can rollback:
```bash
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml stop jwt-validator keycloak keycloak-db
cp custom_server.conf.backup-20260131_013846 custom_server.conf
docker compose -f run_obsidian_remote.yml restart nginx_proxy_manager
```

## Development vs Production

The system is designed for production use:
- Uses `restart: unless-stopped` on critical services
- Persistent data volumes
- Automatic certificate renewal
- Health monitoring via logs

For development, consider:
- Using `dev/` directory for local overrides
- Checking out backup configurations before changes
- Testing changes in `open-webui` service first (simpler)

## OAuth Configuration

The system includes a complete OAuth 2.1 authorization infrastructure for MCP endpoints. See detailed documentation:

- **Implementation guide**: `docs/keycloak-oauth-implementation-summary.md`
- **Environment variables**: `mcp-keycloak-envs.md`
- **Test script**: `docs/test-oauth-setup.sh`
- **Task completion**: `docs/task-log/keycloak-oauth-implementation-completion-2026-01-31.md`

### Keycloak Admin Access

- **URL**: https://alanhoangnguyen.com/oauth/
- **Username**: admin
- **Password**: See `dev/docker-compose.env` (KEYCLOAK_ADMIN_PASSWORD)

### Manual Configuration Required

After deployment, you must configure Keycloak:
1. Create realm: `mcp`
2. Create client: `chatgpt-mcp-client` with PKCE S256
3. Create scopes: `inventory:read`, `inventory:write`
4. Create test user for validation
5. Configure token lifespans (15 minutes recommended)

See `docs/keycloak-oauth-implementation-summary.md` for step-by-step instructions.

### ChatGPT/Claude Integration

Configure MCP connector in Claude Desktop or Web:

**For Inventory Server:**
- **MCP URL**: `https://alanhoangnguyen.com/mcp`
- **Client ID**: `chatgpt-mcp-client`
- **Client Secret**: See `dev/docker-compose.env`

**For Obsidian Vault Server:**
- **MCP URL**: `https://alanhoangnguyen.com/mcp/obsidian`
- **Client ID**: `chatgpt-mcp-client`
- **Client Secret**: See `dev/docker-compose.env`

Both servers use the same OAuth credentials. Claude will automatically discover the OAuth endpoints via `/.well-known/oauth-authorization-server`.
