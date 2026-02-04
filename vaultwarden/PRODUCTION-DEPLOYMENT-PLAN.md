# Vaultwarden Production Deployment Plan
## Corrected for Existing Production Infrastructure

**Date:** 2025-12-23
**Target System:** obsRemote Production Environment
**Status:** Ready for Implementation

---

## Executive Summary

This document provides the **CORRECT** deployment plan for integrating Vaultwarden into the existing obsRemote production system. The original documentation in this directory assumed a standalone deployment, which is **NOT compatible** with our production architecture.

### Key Changes from Original Plan
- ❌ **NO separate nginx container** - Use existing `nginx_proxy_manager`
- ❌ **NO separate certbot container** - Use existing `certbot` service
- ❌ **NO standalone docker-compose.prod.yml** - Integrate into `run_obsidian_remote.yml`
- ✅ **YES integrate with obsidian_network** - Join existing Docker network
- ✅ **YES use existing SSL infrastructure** - Share `npm/letsencrypt/` volume
- ✅ **YES follow existing patterns** - Match architecture of other services

---

## Production Architecture Analysis

### What We Have (Current State)

**Infrastructure Services:**
```
nginx_proxy_manager (happydance/nginx:latest)
├── Ports: 80, 443, 81
├── SSL: npm/letsencrypt/ → /etc/letsencrypt
├── Config: custom_server.conf → /etc/nginx/conf.d/custom_server.conf
└── Network: obsidian_network

certbot (certbot/certbot:latest)
├── Auto-renewal: Every 12 hours
├── SSL: npm/letsencrypt/ → /etc/letsencrypt (SHARED with nginx)
├── Webroot: webroot/ → /var/www/certbot
└── Script: certbot-scripts/renew-certs.sh

Network: obsidian_network (bridge)
├── All 11 existing services
└── Internal DNS by service name
```

**Current Domains Served:**
- alanhoangnguyen.com (main domain)
- openwebui.alanhoangnguyen.com
- helper.alanhoangnguyen.com (PyPI server)
- n8n.alanhoangnguyen.com (n8n workflows)
- registry.alanhoangnguyen.com (Docker registry)
- flofluent.com

**Environment Management:**
- Central file: `dev/docker-compose.env`
- Sourced by all scripts in `script/`
- Contains all API keys, credentials, domain configs

### What We're Adding (Target State)

**New Service:**
```
vaultwarden (vaultwarden/server:latest)
├── Internal Port: 80 (exposed, not published)
├── Data: ./vaultwarden/vw-data → /data
├── Network: obsidian_network (joined)
└── Proxied via: nginx_proxy_manager
```

**New Domain:**
- vault.alanhoangnguyen.com (or your chosen subdomain)

**New Config:**
- Server block in `custom_server.conf`
- Environment variables in `dev/docker-compose.env`
- SSL certificate via existing certbot

---

## Implementation Steps

### Prerequisites

1. **Choose Subdomain** - Decision needed:
   - `vault.alanhoangnguyen.com` (recommended)
   - `vaultwarden.alanhoangnguyen.com`
   - `passwords.alanhoangnguyen.com`
   - Other subdomain of your choice

2. **DNS Configuration** - Must complete BEFORE deployment:
   ```bash
   # Add A record for chosen subdomain
   vault.alanhoangnguyen.com → <your-server-ip>

   # Verify DNS propagation
   dig vault.alanhoangnguyen.com +short
   # Should return your server IP
   ```

3. **Generate Admin Token** - Strong random token:
   ```bash
   openssl rand -base64 48
   # Save this token - you'll need it to access admin panel
   ```

---

### Step 1: Backup Critical Files

**ALWAYS backup before making changes to production:**

```bash
cd /root/Orchestration/obsRemote

# Backup compose file
cp run_obsidian_remote.yml run_obsidian_remote.yml.backup-$(date +%Y%m%d_%H%M%S)

# Backup nginx config
cp custom_server.conf custom_server.conf.backup-$(date +%Y%m%d_%H%M%S)

# Backup environment variables
cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)

# Verify backups
ls -lh *.backup-* custom_server.conf.backup-* dev/*.backup-*
```

---

### Step 2: Create Vaultwarden Data Directory

```bash
cd /root/Orchestration/obsRemote

# Create directory structure
mkdir -p vaultwarden/vw-data

# Set permissions (vaultwarden runs as UID 1000 by default)
chown -R 1000:1000 vaultwarden/

# Verify
ls -la vaultwarden/
```

---

### Step 3: Add Environment Variables

Edit `dev/docker-compose.env` and add these variables at the end:

```bash
# Open the file
nano dev/docker-compose.env
```

**Add these lines:**

```bash
################################################################################
# Vaultwarden Configuration
################################################################################

# Domain (MUST start with https://)
VAULTWARDEN_DOMAIN=https://vault.alanhoangnguyen.com

# Admin token (use the token you generated in prerequisites)
VAULTWARDEN_ADMIN_TOKEN=<paste-your-generated-token-here>

# Optional: SMTP Email Configuration (for password resets, invitations)
# Uncomment and configure if needed:
# VAULTWARDEN_SMTP_HOST=smtp.gmail.com
# VAULTWARDEN_SMTP_FROM=vaultwarden@alanhoangnguyen.com
# VAULTWARDEN_SMTP_PORT=587
# VAULTWARDEN_SMTP_USERNAME=your-email@gmail.com
# VAULTWARDEN_SMTP_PASSWORD=your-app-password
```

**Save and verify:**

```bash
# Test that env vars are readable
source dev/docker-compose.env
echo "Domain: $VAULTWARDEN_DOMAIN"
echo "Token set: ${VAULTWARDEN_ADMIN_TOKEN:0:10}..." # Show first 10 chars only
```

---

### Step 4: Add Vaultwarden Service to Docker Compose

Edit `run_obsidian_remote.yml`:

```bash
nano run_obsidian_remote.yml
```

**Add this service block (place it after the `n8n` service, before `networks`):**

```yaml
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    expose:
      - "80"
    volumes:
      - ./vaultwarden/vw-data:/data
    environment:
      - DOMAIN=${VAULTWARDEN_DOMAIN}
      - ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
      - SIGNUPS_ALLOWED=false
      - INVITATIONS_ALLOWED=true
      - SHOW_PASSWORD_HINT=false
      - WEB_VAULT_ENABLED=true
      - LOG_LEVEL=info
      # Optional SMTP configuration (uncomment if using email)
      # - SMTP_HOST=${VAULTWARDEN_SMTP_HOST:-}
      # - SMTP_FROM=${VAULTWARDEN_SMTP_FROM:-}
      # - SMTP_PORT=${VAULTWARDEN_SMTP_PORT:-587}
      # - SMTP_SECURITY=starttls
      # - SMTP_USERNAME=${VAULTWARDEN_SMTP_USERNAME:-}
      # - SMTP_PASSWORD=${VAULTWARDEN_SMTP_PASSWORD:-}
    networks:
      - obsidian_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/alive"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

**Important notes:**
- **NO ports published to host** - Only `expose: 80` for internal network
- **Uses obsidian_network** - Same network as all other services
- **SIGNUPS_ALLOWED=false** - Security best practice
- **INVITATIONS_ALLOWED=true** - Allows admin to invite users

**Validate syntax:**

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml config > /dev/null
echo "Config validation: $?"
# Should output: Config validation: 0
```

---

### Step 5: Add Nginx Configuration

Edit `custom_server.conf`:

```bash
nano custom_server.conf
```

**First, update the HTTP redirect server block** (around line 4):

Find this line:
```nginx
server_name alanhoangnguyen.com www.alanhoangnguyen.com openwebui.alanhoangnguyen.com helper.alanhoangnguyen.com n8n.alanhoangnguyen.com registry.alanhoangnguyen.com;
```

Change to:
```nginx
server_name alanhoangnguyen.com www.alanhoangnguyen.com openwebui.alanhoangnguyen.com helper.alanhoangnguyen.com n8n.alanhoangnguyen.com registry.alanhoangnguyen.com vault.alanhoangnguyen.com;
```

**Then, add this server block at the end of the file** (after the flofluent.com block):

```nginx
# Vaultwarden Password Manager
server {
    listen 443 ssl http2;
    server_name vault.alanhoangnguyen.com;

    # SSL Configuration (using main certificate with SAN)
    ssl_certificate /etc/letsencrypt/live/alanhoangnguyen.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/alanhoangnguyen.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Vaultwarden proxy
    location / {
        proxy_pass http://vaultwarden:80/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # WebSocket support for push notifications
    location /notifications/hub {
        proxy_pass http://vaultwarden:80/notifications/hub;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /notifications/hub/negotiate {
        proxy_pass http://vaultwarden:80/notifications/hub/negotiate;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Allow large vault exports/imports
    client_max_body_size 50M;

    # Logging
    error_log /var/log/nginx/vaultwarden_error.log;
    access_log /var/log/nginx/vaultwarden_access.log;
}
```

**Test nginx configuration:**

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -t
# Should output: nginx: configuration file /etc/nginx/nginx.conf test is successful
```

---

### Step 6: Request SSL Certificate

You have two options:

#### Option A: Add to Main Certificate (SAN) - Recommended

If your main certificate already uses SANs (Subject Alternative Names), you can add vault.alanhoangnguyen.com to it:

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

# Request expanded certificate
docker compose -f run_obsidian_remote.yml exec certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $CERTBOT_EMAIL \
  --agree-tos \
  --non-interactive \
  --expand \
  -d alanhoangnguyen.com \
  -d www.alanhoangnguyen.com \
  -d openwebui.alanhoangnguyen.com \
  -d helper.alanhoangnguyen.com \
  -d n8n.alanhoangnguyen.com \
  -d vault.alanhoangnguyen.com
```

#### Option B: Separate Certificate

Or create a separate certificate for vaultwarden:

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

docker compose -f run_obsidian_remote.yml exec certbot certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  --email $CERTBOT_EMAIL \
  --agree-tos \
  --non-interactive \
  -d vault.alanhoangnguyen.com
```

**If using Option B**, update the nginx config to use the separate cert:

```nginx
ssl_certificate /etc/letsencrypt/live/vault.alanhoangnguyen.com/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/vault.alanhoangnguyen.com/privkey.pem;
```

**Verify certificate:**

```bash
# Check certificate was created
docker compose -f run_obsidian_remote.yml exec certbot ls -la /etc/letsencrypt/live/

# Or check on host
ls -la npm/letsencrypt/live/
```

---

### Step 7: Start Vaultwarden Service

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

# Start vaultwarden (this will pull the image if needed)
docker compose -f run_obsidian_remote.yml up -d vaultwarden

# Check status
docker compose -f run_obsidian_remote.yml ps vaultwarden

# Check logs
./script/see-logs.sh vaultwarden
```

**Expected output:**
```
[YYYY-MM-DD HH:MM:SS][vaultwarden::api::core][INFO] Rocket has launched from http://0.0.0.0:80
```

---

### Step 8: Reload Nginx

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

# Reload nginx to pick up new configuration
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -s reload

# Verify nginx is running
docker compose -f run_obsidian_remote.yml ps nginx_proxy_manager
```

---

### Step 9: Verify Deployment

**Test from server:**

```bash
# Test HTTP redirect (should return 301)
curl -I http://vault.alanhoangnguyen.com

# Test HTTPS (should return 200)
curl -I https://vault.alanhoangnguyen.com

# Test vaultwarden API
curl https://vault.alanhoangnguyen.com/alive
# Should return: {"status":"ok"}
```

**Test from browser:**

1. Visit `https://vault.alanhoangnguyen.com`
2. You should see the Bitwarden/Vaultwarden login page
3. SSL certificate should be valid (check padlock icon)

---

### Step 10: Initial Configuration

#### Create Your Admin Account

1. Visit `https://vault.alanhoangnguyen.com`
2. Click "Create Account"
3. Enter your email and **master password** (SAVE THIS SECURELY!)
4. Click "Create Account"

**CRITICAL:** Your master password cannot be reset! Store it securely.

#### Access Admin Panel

1. Visit `https://vault.alanhoangnguyen.com/admin`
2. Enter the `VAULTWARDEN_ADMIN_TOKEN` from your env file
3. Review settings:
   - ✅ Verify "Allow new signups" is **disabled**
   - ✅ Verify "Allow invitations" is **enabled**
   - Configure other settings as needed

#### Invite Additional Users (Optional)

1. In admin panel, go to "Users"
2. Click "Invite User"
3. Enter email address
4. User will receive invitation link (if SMTP configured)
5. Or copy the link and send manually

---

### Step 11: Set Up Backups

Create a backup script based on the provided `backup-prod.sh`:

```bash
cd /root/Orchestration/obsRemote

# Create backup script
cat > vaultwarden/backup-vaultwarden.sh << 'EOF'
#!/bin/bash
# Vaultwarden Backup Script

set -e

BACKUP_DIR="/var/backups/vaultwarden"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/vaultwarden_backup_$DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
echo "Creating backup: $BACKUP_FILE"
cd /root/Orchestration/obsRemote
tar -czf "$BACKUP_FILE" vaultwarden/vw-data/

# Keep only last 30 days of backups
find "$BACKUP_DIR" -name "vaultwarden_backup_*.tar.gz" -mtime +30 -delete

echo "Backup complete: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
EOF

# Make executable
chmod +x vaultwarden/backup-vaultwarden.sh

# Test backup
./vaultwarden/backup-vaultwarden.sh
```

**Add to cron for daily backups:**

```bash
# Edit root crontab
crontab -e

# Add this line (daily at 2 AM)
0 2 * * * /root/Orchestration/obsRemote/vaultwarden/backup-vaultwarden.sh >> /var/log/vaultwarden-backup.log 2>&1
```

---

## Post-Deployment Checklist

### Security

- [ ] Master password is strong and stored securely
- [ ] Admin token is strong and stored securely
- [ ] Public signups are disabled (`SIGNUPS_ALLOWED=false`)
- [ ] HTTPS is working with valid SSL certificate
- [ ] Admin panel is accessible at `/admin`
- [ ] WebSocket notifications are working (test with browser extension)

### Functionality

- [ ] Can create account
- [ ] Can login to web vault
- [ ] Can add passwords/items
- [ ] Can create organizations (for sharing)
- [ ] Can invite users (if using invitations)
- [ ] Browser extension works (install from browser store)
- [ ] Mobile app works (install official Bitwarden app, point to your server)

### Operations

- [ ] Service starts automatically (`restart: unless-stopped`)
- [ ] Logs are accessible via `./script/see-logs.sh vaultwarden`
- [ ] Backup script is working
- [ ] Backup cron job is scheduled
- [ ] Monitoring/alerting is configured (optional)

### Testing

- [ ] Test restore from backup:
  ```bash
  # Stop vaultwarden
  docker compose -f run_obsidian_remote.yml stop vaultwarden

  # Restore backup
  cd /root/Orchestration/obsRemote
  rm -rf vaultwarden/vw-data.old
  mv vaultwarden/vw-data vaultwarden/vw-data.old
  tar -xzf /var/backups/vaultwarden/vaultwarden_backup_XXXXXX.tar.gz

  # Restart vaultwarden
  docker compose -f run_obsidian_remote.yml start vaultwarden

  # Verify data is intact
  ```

---

## Maintenance Procedures

### Viewing Logs

```bash
cd /root/Orchestration/obsRemote

# View logs (last 100 lines)
./script/see-logs.sh vaultwarden

# Tail logs (follow mode)
./script/see-logs.sh -t vaultwarden

# View specific number of lines
docker compose -f run_obsidian_remote.yml logs --tail 500 vaultwarden
```

### Updating Vaultwarden

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

# Pull new image
docker pull vaultwarden/server:latest

# Recreate container with new image
docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps vaultwarden

# Check logs to verify successful start
./script/see-logs.sh vaultwarden
```

### Restarting Vaultwarden

```bash
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh

# Restart service
docker compose -f run_obsidian_remote.yml restart vaultwarden

# Verify it's running
docker compose -f run_obsidian_remote.yml ps vaultwarden
```

### Accessing Container Shell

```bash
cd /root/Orchestration/obsRemote

# Shell into vaultwarden container
./script/shell-into.sh vaultwarden sh

# Or directly:
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml exec vaultwarden sh
```

### Manual Backup

```bash
cd /root/Orchestration/obsRemote

# Run backup script
./vaultwarden/backup-vaultwarden.sh

# Or manual backup
tar -czf "/var/backups/vaultwarden/manual_backup_$(date +%Y%m%d_%H%M%S).tar.gz" vaultwarden/vw-data/
```

---

## Troubleshooting

### Service Won't Start

**Check logs:**
```bash
./script/see-logs.sh vaultwarden
```

**Common issues:**
- Environment variables not sourced: `source script/sourceEnv.sh`
- Data directory permissions: `chown -R 1000:1000 vaultwarden/`
- Port conflict (unlikely with internal port): `docker ps | grep 80`

### Can't Access Web Vault

**Check nginx routing:**
```bash
# Test from inside server
curl -I https://vault.alanhoangnguyen.com

# Check nginx logs
docker compose -f run_obsidian_remote.yml logs nginx_proxy_manager | grep vault

# Test nginx config
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager nginx -t
```

**Check DNS:**
```bash
dig vault.alanhoangnguyen.com +short
# Should return your server IP
```

### SSL Certificate Issues

**Check certificate exists:**
```bash
# On host
ls -la npm/letsencrypt/live/alanhoangnguyen.com/
# Or
ls -la npm/letsencrypt/live/vault.alanhoangnguyen.com/

# Inside nginx container
docker compose -f run_obsidian_remote.yml exec nginx_proxy_manager ls -la /etc/letsencrypt/live/
```

**Re-request certificate:**
```bash
# See Step 6 for commands
```

### WebSocket Notifications Not Working

**Check nginx WebSocket config:**
- Ensure `/notifications/hub` location blocks are present in `custom_server.conf`
- Check nginx error logs: `tail -f npm/log/vaultwarden_error.log`

**Test WebSocket from browser console:**
```javascript
const ws = new WebSocket('wss://vault.alanhoangnguyen.com/notifications/hub');
ws.onopen = () => console.log('Connected');
ws.onerror = (e) => console.error('Error:', e);
```

### Admin Panel Shows Wrong Domain

**Update DOMAIN environment variable:**
```bash
# Edit dev/docker-compose.env
nano dev/docker-compose.env

# Ensure VAULTWARDEN_DOMAIN starts with https://
VAULTWARDEN_DOMAIN=https://vault.alanhoangnguyen.com

# Restart vaultwarden
docker compose -f run_obsidian_remote.yml restart vaultwarden
```

### Database Locked Errors

**SQLite database is locked (rare):**
```bash
# Stop vaultwarden
docker compose -f run_obsidian_remote.yml stop vaultwarden

# Wait a few seconds for locks to release
sleep 5

# Start vaultwarden
docker compose -f run_obsidian_remote.yml start vaultwarden
```

---

## Migration from Bitwarden Cloud

If you're migrating from Bitwarden's cloud service:

1. **Export from Bitwarden Cloud:**
   - Login to vault.bitwarden.com
   - Go to Tools → Export Vault
   - Choose format: `.json` (encrypted) or `.csv` (unencrypted)
   - Download export file

2. **Import to Vaultwarden:**
   - Login to your vaultwarden instance
   - Go to Tools → Import Data
   - Select "Bitwarden (json)" or "Bitwarden (csv)"
   - Upload your export file
   - Click "Import Data"

3. **Update Client Apps:**
   - Browser extensions: Settings → Change server URL to `https://vault.alanhoangnguyen.com`
   - Mobile apps: Login screen → Settings (gear icon) → Self-hosted → Enter server URL
   - Desktop app: Settings → Self-hosted environment → Server URL

4. **Verify Import:**
   - Check all items imported correctly
   - Verify attachments (if any) are present
   - Test 2FA if configured

---

## Monitoring and Alerting

### Health Check Endpoint

Vaultwarden includes a health check endpoint:

```bash
curl https://vault.alanhoangnguyen.com/alive
# Response: {"status":"ok"}
```

### Integration with Existing Monitoring

If you use external monitoring (UptimeRobot, Pingdom, etc.):

- **Endpoint:** `https://vault.alanhoangnguyen.com/alive`
- **Expected response:** `200 OK` with `{"status":"ok"}`
- **Check interval:** 5 minutes recommended
- **Alert on:** 3+ consecutive failures

### Resource Monitoring

```bash
# Check container resource usage
docker stats vaultwarden --no-stream

# Expected: Low CPU, moderate memory (~50-100MB)
```

---

## Security Hardening (Optional)

### Disable Admin Panel After Setup

Once configured, you can disable the admin panel entirely:

```bash
# Edit dev/docker-compose.env
nano dev/docker-compose.env

# Remove or comment out VAULTWARDEN_ADMIN_TOKEN
# VAULTWARDEN_ADMIN_TOKEN=

# Restart vaultwarden
docker compose -f run_obsidian_remote.yml restart vaultwarden
```

Re-enable when needed by adding the token back.

### Enable Fail2Ban (Optional)

Create fail2ban rule to block brute force attacks:

```bash
# Create filter
cat > /etc/fail2ban/filter.d/vaultwarden.conf << 'EOF'
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <HOST>\. Username:.*$
ignoreregex =
EOF

# Create jail
cat > /etc/fail2ban/jail.d/vaultwarden.conf << 'EOF'
[vaultwarden]
enabled = true
port = 80,443
filter = vaultwarden
logpath = /root/Orchestration/obsRemote/vaultwarden/vw-data/vaultwarden.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

# Restart fail2ban
systemctl restart fail2ban
```

### Rate Limiting (Already Configured)

Nginx configuration includes basic rate limiting in the proxy headers. For advanced rate limiting, you can add to nginx config:

```nginx
# Add to http block in nginx config (requires editing nginx container config)
limit_req_zone $binary_remote_addr zone=vaultwarden_limit:10m rate=10r/s;

# Then in server block:
location / {
    limit_req zone=vaultwarden_limit burst=20 nodelay;
    # ... rest of proxy config
}
```

---

## Architecture Diagram

```
Internet
   ↓
   ↓ :443 (HTTPS)
   ↓
┌──────────────────────────────────────────┐
│ nginx_proxy_manager                      │
│ ├─ Ports: 80, 443, 81                   │
│ ├─ SSL: npm/letsencrypt/                │
│ └─ Config: custom_server.conf           │
└──────────────────────────────────────────┘
   ↓
   ↓ vault.alanhoangnguyen.com → vaultwarden:80
   ↓
┌──────────────────────────────────────────┐
│ vaultwarden                              │
│ ├─ Port: 80 (internal only)             │
│ ├─ Data: ./vaultwarden/vw-data/         │
│ └─ Network: obsidian_network            │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ certbot (shared SSL)                     │
│ ├─ Runs: Every 12 hours                 │
│ ├─ Certs: npm/letsencrypt/ (shared)     │
│ └─ Renewal: Automatic                   │
└──────────────────────────────────────────┘

All services on: obsidian_network (Docker bridge)
```

---

## Comparison: Original Plan vs Implemented

| Aspect | Original Plan | Implemented Plan |
|--------|--------------|------------------|
| Nginx | Separate container | Use existing nginx_proxy_manager |
| Certbot | Separate container | Use existing certbot |
| Network | vaultwarden-net | obsidian_network |
| Compose file | docker-compose.prod.yml | run_obsidian_remote.yml |
| Port binding | 80:80, 443:443 | Internal only (expose: 80) |
| SSL management | Manual setup | Automatic via existing certbot |
| Env vars | .env.prod | dev/docker-compose.env |
| Scripts | Custom scripts | Use existing obsRemote scripts |

**Result:** Simpler, more integrated, follows existing patterns.

---

## Additional Resources

### Vaultwarden Documentation
- Official Wiki: https://github.com/dani-garcia/vaultwarden/wiki
- Configuration: https://github.com/dani-garcia/vaultwarden/wiki/Configuration-overview
- FAQs: https://github.com/dani-garcia/vaultwarden/wiki/FAQs

### Bitwarden Clients
- Browser Extensions: https://bitwarden.com/download/
- Mobile Apps: iOS App Store, Google Play Store (search "Bitwarden")
- Desktop: https://bitwarden.com/download/
- CLI: https://bitwarden.com/help/cli/

### Security Best Practices
- Master Password Guidelines: https://bitwarden.com/help/master-password/
- Two-Step Login: https://bitwarden.com/help/setup-two-step-login/
- Emergency Access: https://bitwarden.com/help/emergency-access/

---

## Summary

**What we did:**
1. ✅ Integrated vaultwarden into existing obsRemote production system
2. ✅ Reused existing nginx_proxy_manager and certbot infrastructure
3. ✅ Added service to run_obsidian_remote.yml (12th service)
4. ✅ Added nginx routing to custom_server.conf
5. ✅ Added environment variables to dev/docker-compose.env
6. ✅ Configured SSL via existing certbot
7. ✅ Set up backups and monitoring

**What we avoided:**
1. ❌ Duplicate nginx containers
2. ❌ Duplicate certbot containers
3. ❌ Separate docker-compose files
4. ❌ Standalone deployment complexity
5. ❌ Port conflicts
6. ❌ Network isolation issues

**Benefits:**
- Consistent architecture with other services
- Centralized SSL management
- Unified operations (same scripts work for all services)
- Lower resource usage
- Simpler maintenance

---

## Status

**Deployment Status:** Ready for implementation
**Last Updated:** 2025-12-23
**Prepared By:** Claude Code AI Assistant
**Target System:** obsRemote Production Environment (DigitalOcean)

**Next Steps:**
1. Review this document
2. Choose vaultwarden subdomain
3. Configure DNS
4. Execute implementation steps 1-11
5. Complete post-deployment checklist
6. Document any issues or modifications

---

**Questions or Issues?**
- Check troubleshooting section
- Review vaultwarden wiki: https://github.com/dani-garcia/vaultwarden/wiki
- Check service logs: `./script/see-logs.sh vaultwarden`
