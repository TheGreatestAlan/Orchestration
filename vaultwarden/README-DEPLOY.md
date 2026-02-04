# Vaultwarden Production Deployment

## Quick Start

### Option 1: One-Command Deployment
```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/vaultwarden-deploy/main/deploy.sh | bash
```

### Option 2: Manual Setup
```bash
git clone https://github.com/yourusername/vaultwarden-deploy.git
cd vaultwarden-deploy
./setup-vaultwarden.sh
```

### Option 3: Docker Compose Only
```bash
# Download files
curl -O https://raw.githubusercontent.com/yourusername/vaultwarden-deploy/main/docker-compose.prod.yml
curl -O https://raw.githubusercontent.com/yourusername/vaultwarden-deploy/main/nginx.conf

# Configure
cp .env.example .env.prod
nano .env.prod  # Edit your settings

# Deploy
docker compose -f docker-compose.prod.yml up -d
```

## Repository Structure
```
vaultwarden-deploy/
├── setup-vaultwarden.sh      # Main setup script
├── deploy.sh                 # One-command deployment
├── docker-compose.prod.yml   # Production compose file
├── nginx.conf               # Nginx configuration
├── .env.example             # Environment variables template
├── backup-prod.sh           # Backup script
├── setup-ssl.sh             # SSL certificate setup
├── monitor.sh               # Health monitoring
├── restore.sh               # Restore from backup
├── crontab.txt              # Automated tasks
└── README.md                # This file
```

## What the Setup Script Does

1. **Validates Requirements**
   - Docker and Docker Compose installed
   - Docker daemon running

2. **Interactive Configuration**
   - Domain name
   - Admin email
   - Admin token (auto-generated or manual)
   - SMTP settings (optional)

3. **Generates Configuration Files**
   - `docker-compose.prod.yml` - Production containers
   - `nginx.conf` - Reverse proxy with SSL
   - `.env.prod` - Environment variables
   - `setup-ssl.sh` - Let's Encrypt automation

4. **Deploys Containers**
   - Vaultwarden with security hardening
   - Nginx reverse proxy
   - Certbot for SSL certificates

5. **Provides Next Steps**
   - SSL certificate setup
   - Initial user creation
   - Backup configuration

## Post-Deployment

### 1. Set up SSL
```bash
./setup-ssl.sh your-domain.com your-email@example.com
```

### 2. Create Admin Account
- Visit: `https://your-domain.com`
- Click "Create Account" (signups are enabled temporarily)
- Save your master password!

### 3. Secure Your Instance
- Login to admin panel: `https://your-domain.com/admin`
- Use the admin token from setup
- Disable public signups
- Invite users as needed

### 4. Set up Backups
```bash
# Add to crontab
sudo cp crontab.txt /etc/cron.d/vaultwarden
```

## Security Features

- ✅ HTTPS with modern TLS configuration
- ✅ Rate limiting on API endpoints
- ✅ Admin panel protection
- ✅ Security headers (HSTS, CSP, etc.)
- ✅ Brute force protection via rate limiting
- ✅ Zero-knowledge encryption

## Monitoring

Check health status:
```bash
./monitor.sh
```

View logs:
```bash
docker compose -f docker-compose.prod.yml logs -f
```

## Backup & Restore

Create backup:
```bash
./backup-prod.sh
```

Restore from backup:
```bash
./restore-prod.sh backup-file.tar.gz
```

## Updates

Update Vaultwarden:
```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

## Troubleshooting

### Container won't start
- Check logs: `docker compose -f docker-compose.prod.yml logs`
- Verify port 80/443 are free: `sudo netstat -tulpn | grep -E ':(80|443)'`

### SSL certificate issues
- Run: `./setup-ssl.sh` again
- Check: `docker compose -f docker-compose.prod.yml logs certbot`

### Can't access admin panel
- Verify token: `grep ADMIN_TOKEN .env.prod`
- Check nginx logs: `docker compose -f docker-compose.prod.yml logs nginx`

## Support

- [Vaultwarden Documentation](https://github.com/dani-garcia/vaultwarden/wiki)
- [Report Issues](https://github.com/yourusername/vaultwarden-deploy/issues)

## License

This deployment script is provided as-is for educational and personal use.