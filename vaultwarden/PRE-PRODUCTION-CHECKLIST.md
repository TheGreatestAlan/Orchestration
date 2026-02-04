# Vaultwarden Pre-Production Checklist

## Security Configuration
- [ ] **Disable Public Signups** - Set `SIGNUPS_ALLOWED=false` after creating admin account
- [ ] **Disable Password Hints** - Already set to `false`
- [ ] **Admin Token** - Ensure strong token is set
- [ ] **Rate Limiting** - Configure via nginx or admin panel
- [ ] **IP Blocking** - Set up fail2ban for brute force protection

## Data & Backup
- [ ] **Backup Location** - Decide where to store backups (S3, local, etc.)
- [ ] **Backup Script** - Create automated backup script
- [ ] **Backup Schedule** - Set up cron job for regular backups
- [ ] **Restore Test** - Verify backup files can be restored
- [ ] **Data Directory** - Ensure `vw-data` is on persistent storage

## Email Configuration
- [ ] **SMTP Provider** - Choose email service (SendGrid, AWS SES, etc.)
- [ ] **SMTP Settings** - Configure in production .env file
- [ ] **Test Email** - Verify password reset emails work
- [ ] **Email Templates** - Customize if needed

## SSL/TLS Setup
- [ ] **Domain** - Purchase/register your domain
- [ ] **SSL Certificate** - Set up Let's Encrypt or purchase certificate
- [ ] **Certificate Renewal** - Configure auto-renewal
- [ ] **Security Headers** - Configure HSTS, CSP, etc.

## Monitoring & Logging
- [ ] **Health Checks** - Set up container health monitoring
- [ ] **Log Aggregation** - Configure log shipping (optional)
- [ ] **Uptime Monitoring** - Set up external monitoring
- [ ] **Alerting** - Configure alerts for downtime

## Database (Optional)
- [ ] **Database Choice** - SQLite (default) vs PostgreSQL
- [ ] **Connection Limits** - Configure if using PostgreSQL
- [ ] **Database Backups** - Set up separate DB backups

## Production Environment
- [ ] **Server Specs** - Ensure adequate CPU/RAM
- [ ] **Firewall Rules** - Configure UFW/iptables
- [ ] **OS Updates** - Set up automatic security updates
- [ ] **SSH Hardening** - Disable root, use keys, etc.

## Deployment
- [ ] **Docker Version** - Update to latest stable
- [ ] **Image Updates** - Plan for Vaultwarden updates
- [ ] **Zero-Downtime Updates** - Test rolling updates
- [ ] **Rollback Plan** - Document rollback procedure

## User Management
- [ ] **Organization Setup** - Create organization for sharing
- [ ] **User Invitations** - Test invitation system
- [ ] **Collection Management** - Set up shared collections
- [ ] **Permissions** - Configure user roles

## Final Testing
- [ ] **Create Test Account** - Verify signup works
- [ ] **Password Storage** - Test saving/retrieving passwords
- [ ] **2FA Setup** - Test TOTP authentication
- [ ] **Mobile App** - Test with Bitwarden mobile app
- [ ] **Browser Extension** - Test browser integration
- [ ] **Sharing** - Test organization password sharing
- [ ] **Export** - Test data export functionality

## Documentation
- [ ] **User Guide** - Document how to use for your users
- [ ] **Admin Guide** - Document admin procedures
- [ ] **Emergency Access** - Set up emergency access
- [ ] **Recovery Procedures** - Document disaster recovery

## Compliance (If Applicable)
- [ ] **GDPR Compliance** - Data protection requirements
- [ ] **Audit Logging** - Enable if required
- [ ] **Data Retention** - Configure retention policies
- [ ] **Access Logs** - Set up access monitoring

## Performance
- [ ] **Load Testing** - Test with expected user load
- [ ] **Response Times** - Monitor API response times
- [ ] **Resource Usage** - Monitor CPU/memory usage
- [ ] **Network Optimization** - Check CDN/cloudflare options

---

## Quick Start Commands

### Create Admin Account
```bash
# Access web vault
open http://localhost:8080
# Sign up with your email
```

### Disable Signups (After account creation)
```bash
# Edit docker-compose.yml
SIGNUPS_ALLOWED=false
# Restart
docker compose down && docker compose up -d
```

### Backup Data
```bash
# Create backup
tar -czf "backup-$(date +%Y%m%d).tar.gz" vw-data/
```

### Monitor Logs
```bash
# View logs
docker compose logs -f
```

---

## Status
**Current Phase**: Local Development Complete
**Next**: Complete checklist items before production deployment
**Ready for**: User testing and final configuration