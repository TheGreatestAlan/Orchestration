# CLAUDE.md - Technical Documentation for AI Assistants

## System Overview

This is a **production Docker Compose orchestration** managing 12 containerized services. It's described as "small and scrappy" but serves multiple production domains with SSL, VPN, private registries, and AI agents.

## Critical Working Rules

### 1. Environment Variables Are MANDATORY

**Before ANY docker compose command**, the environment MUST be sourced:

```bash
source script/sourceEnv.sh
# OR
source dev/docker-compose.env
```

The env file location is: `dev/docker-compose.env` (NOT `script/docker-compose.env` which is just a 6-line template)

All scripts in `script/` already handle this for you:
- `setEnvAndRun.sh` - sources env then runs compose
- `see-logs.sh` - sources env then shows logs
- `shell-into.sh` - sources env then shells in
- `pullNewImages.sh` - sources env then updates images

### 2. Working Directory

Always work from `obsRemote/` directory when running docker compose commands:

```bash
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml <command>
```

### 3. The Compose File

Main compose file: `run_obsidian_remote.yml`

**DO NOT** edit this file without creating a timestamped backup first:
```bash
cp run_obsidian_remote.yml run_obsidian_remote.yml.backup-$(date +%Y%m%d_%H%M%S)
```

## Service Architecture

### Service Dependencies & Communication

All services communicate via the `obsidian_network` Docker bridge. They can reference each other by service name:

```yaml
agent-server:
  environment:
    - ORGANIZER_SERVER_URL=http://organizerserver:8080  # Direct service name
    - SCHEDULER_URL=http://scheduler:8080
```

**External Access Pattern:**
```
Internet → :443 (nginx) → internal service (nginx_proxy_manager routes by hostname)
```

**Internal Access Pattern:**
```
service-a → http://service-b:port (direct via service name)
```

### Service Breakdown

#### 1. organizerserver (happydance/organizerserver:latest)
- Manages git repositories
- Handles Obsidian vault operations
- **No exposed ports** (internal only)
- Mounts: `/obsidian` vault location
- Network: obsidian_network

#### 2. updater (happydance/updater:latest)
- Syncs Obsidian vault locations
- Uses Google credentials (GUSERNAME, GPASSWORD, GTOKEN)
- **No restart policy** (runs on demand)
- Mounts: `$OBSIDIAN_VAULTS` to `/app/vault`

#### 3. agent-server (registry.alanhoangnguyen.com/admin/agent-server:latest)
- **Main AI service** - multi-model LLM support
- REST API: configurable via `$AGENT_SERVER_REST_PORT`
- WebSocket: `$WS_PORT` (default 12346) - **bound to localhost only**
- Models configurable via env vars (MODEL_COMMAND_PARSER, MODEL_REACT_PLAN, etc.)
- Firebase auth required (firebase/FirebaseServiceAccountKey.json)
- Persistent data:
  - `agent-server/logs/` → `/app/logs`
  - `agent-server/user/` → `/app/user`
  - `agent-server/firebase/` → `/app/firebase`
- **Critical**: Uses inventory API at `$INVENTORY_API_BASE_URL`
- restart: unless-stopped

#### 4. translator (happydance/translator:latest)
- Fireworks AI powered translation
- Port 8080 internally
- Used as backend for open-webui
- restart: unless-stopped

#### 5. open-webui (ghcr.io/open-webui/open-webui:main)
- Web UI for LLM interaction
- Points to translator via `OLLAMA_BASE_URL=http://translator:8080`
- Data: `dev/open-webui/` → `/app/backend/data`
- restart: unless-stopped

#### 6. nginx_proxy_manager (happydance/nginx:latest)
- **Critical infrastructure** - all traffic flows through here
- Ports:
  - 80 → HTTP (redirects to HTTPS)
  - 81 → Admin UI
  - 443 → HTTPS
- Custom config: `custom_server.conf` → `/etc/nginx/conf.d/custom_server.conf`
- Certificates: `npm/letsencrypt/` → `/etc/letsencrypt`
- Depends on certbot for SSL
- restart: unless-stopped

#### 7. docker-registry (registry:2)
- Private Docker registry at registry.alanhoangnguyen.com
- Port 5000 internally
- Auth: htpasswd (`registry/auth/htpasswd`)
- Storage: `registry/data/` → `/var/lib/registry`
- **Delete enabled** via `REGISTRY_STORAGE_DELETE_ENABLED=true`
- restart: unless-stopped

#### 8. pypi-server (pypiserver/pypiserver:latest)
- Private Python package repository
- Available at helper.alanhoangnguyen.com/pypi/
- Port 8080 internally
- Packages: `/root/pypi-packages` → `/data/packages`
- Auth: `/root/pypi-auth` → `/data/auth`
- Command: `run -p 8080 -a update -P /data/auth/.htpasswd /data/packages`
- restart: unless-stopped

#### 9. certbot (certbot/certbot:latest)
- Automated SSL certificate management
- Runs renewal check every 12 hours
- Uses HTTP-01 challenge (webroot method)
- Shares `webroot/` with nginx for challenges
- Script: `certbot-scripts/renew-certs.sh`
- Domains managed: See `$CERTBOT_DOMAINS` in env
- restart: unless-stopped

#### 10. wireguard (lscr.io/linuxserver/wireguard:latest)
- VPN server
- Port: `$SERVERPORT` (default 51820/udp)
- Requires `NET_ADMIN` and `SYS_MODULE` caps
- Config: `wireguard-config/` → `/config`
- restart: unless-stopped

#### 11. scheduler (happydance/scheduler:latest)
- Task scheduling service
- Port: `$SCHEDULER_PORT` (default 8080)
- Helper URL: `http://helper:8080`
- Storage: `scheduler_data/scheduler_tasks.json`
- restart: unless-stopped

#### 12. n8n (n8nio/n8n)
- Workflow automation at n8n.alanhoangnguyen.com
- Basic auth protected
- Data: `n8n_data/` → `/home/node/.n8n`
- Webhook URL configured
- restart: unless-stopped

#### 13. vaultwarden (vaultwarden/server:latest)
- Self-hosted password manager at vault.alanhoangnguyen.com
- Bitwarden-compatible API (works with all Bitwarden clients)
- Port 80 internally (exposed, not published)
- Data: `vaultwarden/vw-data/` → `/data`
- Environment:
  - `DOMAIN=${VAULTWARDEN_DOMAIN}` - Must start with https://
  - `ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}` - Admin panel access
  - `SIGNUPS_ALLOWED=false` - Public signups disabled for security
  - `INVITATIONS_ALLOWED=true` - Admin can invite users
  - `WEB_VAULT_ENABLED=true` - Web interface enabled
- Features:
  - End-to-end encrypted vault (master password never sent to server)
  - WebSocket support for push notifications (/notifications/hub)
  - Admin panel at `/admin` (requires ADMIN_TOKEN)
  - Health check endpoint: `/alive`
  - SQLite database (db.sqlite3)
- Backups:
  - Automated daily backups at 2:00 AM
  - Script: `vaultwarden/backup-vaultwarden.sh`
  - Location: `/var/backups/vaultwarden/`
  - Retention: 30 days
  - Restore guide: `vaultwarden/RESTORE.md`
- Security:
  - Runs as UID 1000:1000
  - No external port exposure (proxied via nginx)
  - Client uploads limited to 50M
  - HSTS and security headers enforced by nginx
- restart: unless-stopped

## Common Operations

### Checking Service Status

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml ps
```

Or use docker commands directly:
```bash
docker ps --filter "network=obsidian_network"
```

### Viewing Logs

**Preferred (uses helper script):**
```bash
./script/see-logs.sh agent-server
./script/see-logs.sh -t nginx_proxy_manager  # tail mode
```

**Direct:**
```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml logs -f agent-server
```

### Shell Access

**Preferred:**
```bash
./script/shell-into.sh agent-server bash
```

**Direct:**
```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec -it agent-server bash
```

### Restarting a Single Service

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml restart agent-server
```

### Updating a Single Service

1. Pull new image:
```bash
docker pull registry.alanhoangnguyen.com/admin/agent-server:latest
```

2. Recreate just that service:
```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps agent-server
```

### Full System Update

```bash
cd /root/Orchestration/obsRemote
./script/pullNewImages.sh  # Smart update - only pulls changed images
# OR
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml pull
docker compose -f run_obsidian_remote.yml up -d
```

## Configuration Files

### dev/docker-compose.env

**THIS IS THE SINGLE SOURCE OF TRUTH FOR ALL ENVIRONMENT VARIABLES**

Contains sensitive credentials:
- Git tokens (GIT_TOKEN)
- API keys (FIREWORKS_API_KEY, OPENAI_API_KEY)
- User credentials (GUSERNAME, GPASSWORD)
- Encryption keys (USER_ENCRYPTION_KEY, ENCRYPTION_PASSWORD)
- Domain configuration
- Service ports

**When modifying:**
1. Always backup first: `cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)`
2. Ensure all required variables are present
3. Test with a single service first
4. Restart affected services

### custom_server.conf

Nginx configuration for routing. Currently only has PyPI server config visible, but likely routes all domains.

**Pattern observed:**
```nginx
server {
    listen 443 ssl http2;
    server_name helper.alanhoangnguyen.com;

    ssl_certificate /etc/letsencrypt/live/helper.alanhoangnguyen.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/helper.alanhoangnguyen.com/privkey.pem;

    location /pypi/ {
        proxy_pass http://pypi-server:8080/;
        # ... proxy headers
    }
}
```

**When adding new services:**
1. Add server block
2. Configure SSL cert path
3. Set up proxy_pass to service:port
4. Reload nginx: `docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload`

### run_obsidian_remote.yml

**Modification Safety Checklist:**
- [ ] Backup with timestamp
- [ ] Check all env var references are defined
- [ ] Verify volume paths exist on host
- [ ] Ensure network is `obsidian_network` for all services
- [ ] Test with `docker compose -f run_obsidian_remote.yml config` first
- [ ] Use `up -d --no-deps <service>` to test single service changes

## Networking Deep Dive

### Port Mapping Strategy

**Exposed to host:**
- 80, 81, 443 → nginx_proxy_manager
- 51820/udp → wireguard
- 127.0.0.1:12346 → agent-server WebSocket (localhost only!)

**Internal only (service:port):**
- organizerserver:8080
- translator:8080
- pypi-server:8080
- docker-registry:5000
- scheduler:8080
- helper:8080 (referenced by scheduler)
- vaultwarden:80

### DNS/Domain Routing

Nginx handles routing by server_name:
- alanhoangnguyen.com
- www.alanhoangnguyen.com
- openwebui.alanhoangnguyen.com
- helper.alanhoangnguyen.com (PyPI)
- n8n.alanhoangnguyen.com
- registry.alanhoangnguyen.com (Docker registry)
- vault.alanhoangnguyen.com (Vaultwarden password manager)
- flofluent.com
- www.flofluent.com

All require valid DNS A records pointing to the server IP.

## Security Considerations

### Credentials Management

1. **Never commit** `dev/docker-compose.env` with real credentials
2. **Never log** sensitive env vars
3. **Rotate regularly**:
   - Git tokens
   - API keys
   - htpasswd files

### Service Isolation

- Agent server WebSocket is `127.0.0.1` only - good!
- All HTTP redirects to HTTPS - good!
- Registry requires auth - good!
- PyPI requires auth - good!
- Vaultwarden admin panel requires token - good!
- Vaultwarden public signups disabled - good!

### Volume Permissions

Check ownership on mounted volumes:
```bash
ls -la obsRemote/agent-server/logs/
ls -la obsRemote/registry/data/
ls -la obsRemote/vaultwarden/vw-data/  # Should be 1000:1000
```

Most services run as root or specific UIDs (PUID/PGID for wireguard, UID 1000 for vaultwarden).

## SSL/TLS Management

**CRITICAL**: ALL SSL certificates are managed by the `certbot` container, NOT manually!

### How It Works

The certbot and nginx containers share certificates via Docker volumes:

```yaml
certbot:
  volumes:
    - ./npm/letsencrypt:/etc/letsencrypt  # Certbot writes certs here
    - ./webroot:/var/www/certbot          # For ACME HTTP-01 challenges

nginx_proxy_manager:
  volumes:
    - ./npm/letsencrypt:/etc/letsencrypt  # Nginx reads certs here
    - ./webroot:/var/www/certbot          # For ACME HTTP-01 challenges
```

**Certificate flow:**
1. Certbot obtains/renews certs and writes to `/etc/letsencrypt` (inside container)
2. This maps to `./npm/letsencrypt` on the host
3. Nginx reads from the same `/etc/letsencrypt` mount (shared volume)
4. Both containers access the same physical certificates!

### Certificate Lifecycle

1. **Initial creation**: Certbot obtains certs on first run when domain DNS is configured
2. **Renewal**: Automated every 12 hours by certbot container (runs `/scripts/renew-certs.sh`)
3. **Verification**: Check `npm/letsencrypt/live/<domain>/` on the HOST (not inside containers)

### Adding New Domains

1. Add to `CERTBOT_DOMAINS` in `dev/docker-compose.env` (comma-separated)
2. Ensure DNS A record points to your server IP
3. Create nginx server block in `custom_server.conf` with proper cert paths:
   ```nginx
   ssl_certificate /etc/letsencrypt/live/newdomain.com/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/newdomain.com/privkey.pem;
   ```
4. Request cert manually first time:
```bash
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $CERTBOT_EMAIL \
  --agree-tos \
  --non-interactive \
  -d newdomain.com
```
5. Reload nginx:
```bash
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload
```

### Troubleshooting SSL

**Certificate not found:**
```bash
# Check on HOST filesystem
ls -la npm/letsencrypt/live/

# Check inside certbot container
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec certbot ls -la /etc/letsencrypt/live/

# Check inside nginx container
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager ls -la /etc/letsencrypt/live/
```

**Renewal failing:**
```bash
./script/see-logs.sh certbot
# Check webroot is mounted correctly (./webroot should exist)
# Verify domain DNS points to server
# Test ACME challenge path: curl http://domain.com/.well-known/acme-challenge/
# Check nginx config allows access to /.well-known/acme-challenge/
```

**Certificates out of sync:**
- Certificates are stored on the host at `npm/letsencrypt/`
- Both containers mount this same directory
- No sync needed - they're always in sync via shared volume!

## Data Persistence & Backups

### Critical Data Locations

**Must backup:**
- `dev/docker-compose.env` - ALL configuration
- `agent-server/user/` - User data
- `agent-server/firebase/` - Firebase credentials
- `registry/data/` - Docker images
- `registry/auth/htpasswd` - Registry auth
- `/root/pypi-packages` - Python packages
- `npm/letsencrypt/` - SSL certificates
- `n8n_data/` - Workflows
- `scheduler_data/` - Scheduled tasks
- `wireguard-config/` - VPN configs
- `vaultwarden/vw-data/` - Password vault database (CRITICAL - has automated daily backups)

**Can regenerate:**
- `agent-server/logs/` - Logs
- `npm/log/` - Nginx logs
- `npm/data/` - Proxy manager config (if you have backups)

### Backup Strategy

```bash
# Full backup
cd /root/Orchestration
tar -czf obsRemote-backup-$(date +%Y%m%d).tar.gz \
  obsRemote/dev/docker-compose.env \
  obsRemote/agent-server/user/ \
  obsRemote/agent-server/firebase/ \
  obsRemote/registry/data/ \
  obsRemote/registry/auth/htpasswd \
  obsRemote/npm/letsencrypt/ \
  obsRemote/n8n_data/ \
  obsRemote/scheduler_data/ \
  obsRemote/wireguard-config/ \
  obsRemote/vaultwarden/vw-data/ \
  obsRemote/custom_server.conf \
  obsRemote/run_obsidian_remote.yml

# Exclude large package repos if needed
```

**Vaultwarden Automated Backups:**
- Script: `vaultwarden/backup-vaultwarden.sh`
- Schedule: Daily at 2:00 AM (via cron)
- Location: `/var/backups/vaultwarden/`
- Format: `vaultwarden_backup_YYYYMMDD_HHMMSS.tar.gz`
- Retention: 30 days (automatic cleanup)
- Logs: `/var/log/vaultwarden-backup.log`
- Restore: See `vaultwarden/RESTORE.md`

## Troubleshooting Guide

### Service Won't Start

1. Check env is sourced: `echo $AGENT_SERVER_REST_ADDRESS`
2. Check logs: `./script/see-logs.sh <service>`
3. Check previous container logs: `docker logs <container-name>`
4. Verify volume paths exist: `ls -la agent-server/`
5. Check port conflicts: `netstat -tlnp | grep <port>`

### Network Issues

```bash
# List all networks
docker network ls

# Inspect obsidian_network
docker network inspect obsidian_network

# Verify service can reach another
docker compose -f run_obsidian_remote.yml exec agent-server ping translator
docker compose -f run_obsidian_remote.yml exec agent-server curl http://organizerserver:8080
```

### Nginx Routing Issues

1. Check nginx config syntax:
```bash
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -t
```

2. Check nginx is running:
```bash
docker compose -f run_obsidian_remote.yml ps nginx_proxy_manager
```

3. Test proxy:
```bash
curl -H "Host: helper.alanhoangnguyen.com" http://localhost/pypi/
```

4. Check nginx logs:
```bash
tail -f npm/log/error.log
```

### Agent Server Issues

Most complex service, common issues:

**Firebase auth failing:**
- Check `agent-server/firebase/FirebaseServiceAccountKey.json` exists
- Verify JSON is valid: `cat agent-server/firebase/FirebaseServiceAccountKey.json | jq`

**Model errors:**
- Check FIREWORKS_API_KEY is set
- Verify model names match available models (MODEL_REACT_PLAN, etc.)
- Check LLM logs: `tail -f agent-server/logs/llm.log`

**WebSocket not connecting:**
- Verify WS_PORT matches between env and client
- Check port is bound: `netstat -tlnp | grep 12346`
- Ensure using localhost/127.0.0.1, not external IP

### Registry Issues

**Push/pull failing:**
```bash
# Test auth
docker login registry.alanhoangnguyen.com

# Check registry is running
curl -u admin:password https://registry.alanhoangnguyen.com/v2/_catalog

# Verify htpasswd exists
ls -la registry/auth/htpasswd
```

## Development Workflow

### Testing Changes

1. Always work in a separate branch/backup
2. Test single service first: `docker compose up -d --no-deps <service>`
3. Check logs immediately: `./script/see-logs.sh <service>`
4. Verify service is healthy: `docker ps`
5. Test integration with dependent services

### Adding New Services

Template:
```yaml
new-service:
  image: org/image:tag
  container_name: new_service  # optional but helpful
  restart: unless-stopped
  environment:
    - ENV_VAR=$ENV_VAR_FROM_FILE
  volumes:
    - ./new-service-data:/app/data
  networks:
    - obsidian_network
  # ports:  # only if external access needed
  #   - "127.0.0.1:PORT:PORT"  # prefer localhost binding
```

Add to `custom_server.conf` if needs domain access.

### Image Building

Services use pre-built images. If building custom:
```bash
# Build and push to private registry
docker build -t registry.alanhoangnguyen.com/admin/service:latest .
docker login registry.alanhoangnguyen.com
docker push registry.alanhoangnguyen.com/admin/service:latest
```

## Monitoring & Health Checks

### Quick Health Check

```bash
docker ps --filter "network=obsidian_network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Service-Specific Checks

**Agent server:**
```bash
curl http://localhost:8080/health  # if health endpoint exists
tail -f agent-server/logs/general.log
```

**Nginx:**
```bash
curl -I http://localhost
curl -I https://alanhoangnguyen.com
```

**Registry:**
```bash
curl -k https://registry.alanhoangnguyen.com/v2/
```

**N8N:**
```bash
curl -I https://n8n.alanhoangnguyen.com
```

## Performance Considerations

### Resource Usage

Check with:
```bash
docker stats --no-stream
```

**Heavy services:**
- agent-server (LLM processing)
- open-webui (web interface)
- n8n (workflow automation)

**Light services:**
- certbot (runs every 12h)
- translator (on-demand)
- updater (on-demand)

### Optimization Tips

1. **Prune regularly**: `docker system prune -a --volumes` (CAREFUL with volumes!)
2. **Limit logs**: Add logging config to services
3. **Monitor disk**: `df -h` - registry and pypi can grow large
4. **Registry cleanup**: Use `REGISTRY_STORAGE_DELETE_ENABLED=true` + garbage collection

## Git Status Notes

Currently uncommitted:
- `obsRemote/run_obsidian_remote.yml` (modified)
- `obsRemote/custom_server.conf` (untracked)

This suggests active development. Check git log for recent changes:
```bash
git log --oneline -10
# Recent commits:
# - updated agent server with inventory functionality
# - flofluent
# - registry changes
# - adding certbot
```

## Emergency Procedures

### Complete System Restart

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml down
# Wait 10 seconds
docker compose -f run_obsidian_remote.yml up -d
```

### Rollback Changes

```bash
# Restore compose file
cp run_obsidian_remote.yml.backup-TIMESTAMP run_obsidian_remote.yml

# Restore env
cp dev/docker-compose.env.backup-TIMESTAMP dev/docker-compose.env

# Restart
docker compose -f run_obsidian_remote.yml down
docker compose -f run_obsidian_remote.yml up -d
```

### Nuclear Option (Full Reset)

```bash
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml down -v  # DELETES VOLUMES!
docker system prune -a
# Restore from backups
# Restart from scratch
```

## Summary for Quick Reference

**To start system:**
```bash
cd /root/Orchestration/obsRemote && ./script/setEnvAndRun.sh
```

**To view logs:**
```bash
./script/see-logs.sh -t <service-name>
```

**To shell into service:**
```bash
./script/shell-into.sh <service-name>
```

**To update images:**
```bash
./script/pullNewImages.sh
```

**To stop system:**
```bash
./script/down.sh
```

**Key files:**
- Config: `dev/docker-compose.env`
- Compose: `run_obsidian_remote.yml`
- Nginx: `custom_server.conf`
- Scripts: `script/*.sh`

**Key services:**
- agent-server: Main AI agent
- nginx_proxy_manager: Reverse proxy
- certbot: SSL management
- registry: Private Docker registry
- pypi-server: Private Python packages
