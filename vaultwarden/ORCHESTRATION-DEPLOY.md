# Vaultwarden Deployment on DigitalOcean Server

## Server Details
- **Host**: DigitalOcean Droplet
- **SSH Access**: `ssh root@digitalocean` (from current machine)
- **Deployment Path**: `/root/Orchestration/vaultwarden/`
- **Docker**: Installed (v27.1.2)
- **Docker Compose**: Not installed (will use `docker compose`)

## Quick Deploy on Server

### 1. Connect to Server
```bash
ssh -i ~/.ssh/id_ed25519 root@digitalocean
```

### 2. Navigate to Deployment Directory
```bash
cd /root/Orchestration/vaultwarden/
```

### 3. Run Deployment
```bash
./setup-vaultwarden.sh
```

### 4. Configure Domain
After deployment, you'll need to:
- Point your domain's A record to the server's IP address
- Run SSL setup: `./setup-ssl.sh your-domain.com your-email@example.com`

## Server-Specific Considerations

### Docker Compose
The server has Docker but not the separate `docker-compose` binary. Our scripts use the newer `docker compose` syntax.

### Firewall
Check if ports are open:
```bash
# On server
ufw status
# or
iptables -L
```

### SSL Certificates
Let's Encrypt requires ports 80 and 443 to be accessible.

### Backup Location
Backups are stored in: `/var/backups/vaultwarden/`

## Post-Deployment Steps

1. **Create Admin Account**
   - Visit `http://your-domain.com` (before SSL)
   - Or `https://your-domain.com` (after SSL)

2. **Secure Instance**
   - Login to admin: `https://your-domain.com/admin`
   - Use admin token from setup
   - Disable public signups

3. **Set up Automated Backups**
   ```bash
   # On server
   cp crontab.txt /etc/cron.d/vaultwarden
   ```

## Monitoring

Check status:
```bash
# On server
cd /root/Orchestration/vaultwarden/
./monitor.sh
```

View logs:
```bash
docker compose -f docker-compose.prod.yml logs -f
```

## Troubleshooting

### Can't connect to server
- Verify SSH key: `ssh -i ~/.ssh/id_ed25519 root@digitalocean`
- Check server is running: `ping digitalocean`

### Deployment fails
- Check Docker: `docker ps`
- View logs: `docker compose -f docker-compose.prod.yml logs`
- Verify ports: `netstat -tulpn | grep -E ':(80|443)'`

### Domain not working
- Check DNS: `dig your-domain.com`
- Verify IP matches server: `curl ifconfig.me`

## Security Notes

1. **Change default passwords** after deployment
2. **Enable firewall** if not already enabled
3. **Regular updates**: `docker compose -f docker-compose.prod.yml pull`
4. **Monitor logs** for suspicious activity

## Files on Server

All deployment files are located in:
```
/root/Orchestration/vaultwarden/
├── setup-vaultwarden.sh      # Main setup script
├── docker-compose.prod.yml   # Production containers
├── nginx.conf               # Reverse proxy config
├── monitor.sh               # Health checks
├── backup.sh                # Backup script
└── ...                      # Other deployment files
```

## Next Steps

1. Run `./setup-vaultwarden.sh` to start deployment
2. Configure your domain DNS
3. Set up SSL certificates
4. Create your admin account
5. Enable 2FA and secure the instance