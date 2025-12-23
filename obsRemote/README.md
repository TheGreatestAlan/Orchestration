# obsRemote Production System

A small, scrappy Docker Compose-based production system hosting multiple microservices for AI agents, workflow automation, private registries, and VPN access.

## Architecture Overview

This system runs 12 containerized services orchestrated via Docker Compose:

### Core AI Services
- **organizerserver** - Manages git repositories and Obsidian vault operations
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
└── webroot/                   # Certbot webroot for challenges
```

## Environment Setup

**CRITICAL**: All services require environment variables defined in `dev/docker-compose.env` (NOT `script/docker-compose.env` which is just a template). This file contains:

- **Git credentials** - For Obsidian vault syncing
- **API keys** - Fireworks AI, OpenAI
- **Service ports** - REST, WebSocket endpoints
- **Domain configuration** - Multiple domains served
- **SSL email** - For Let's Encrypt notifications
- **Encryption keys** - User data encryption
- **Auth credentials** - n8n, registry, PyPI

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
