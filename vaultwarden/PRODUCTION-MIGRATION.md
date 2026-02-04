# Vaultwarden Production Migration Guide

## Overview
This guide explains how to migrate from local development (localhost:8080) to production with nginx reverse proxy and HTTPS.

## Local Development (Current)
- Direct HTTP access on localhost:8080
- No reverse proxy
- SQLite database (default)
- Signups enabled for testing

## Production Migration Steps

### 1. Update Domain Configuration
```bash
# In .env file, change:
DOMAIN=https://your-domain.com
```

### 2. Docker Compose for Production
Create `docker-compose.prod.yml`:
```yaml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    # Remove port mapping - nginx will proxy
    expose:
      - "80"
    volumes:
      - ./vw-data:/data
    environment:
      - DOMAIN=https://your-domain.com
      - ADMIN_TOKEN=${ADMIN_TOKEN}
      # Production security settings
      - SIGNUPS_ALLOWED=false
      - INVITATIONS_ALLOWED=true
      - SHOW_PASSWORD_HINT=false
      # Email configuration
      - SMTP_HOST=${SMTP_HOST}
      - SMTP_FROM=${SMTP_FROM}
      - SMTP_PORT=587
      - SMTP_SECURITY=starttls
      - SMTP_USERNAME=${SMTP_USERNAME}
      - SMTP_PASSWORD=${SMTP_PASSWORD}
    networks:
      - vaultwarden-net

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./letsencrypt:/etc/letsencrypt:ro
    depends_on:
      - vaultwarden
    networks:
      - vaultwarden-net

networks:
  vaultwarden-net:
    driver: bridge
```

### 3. Nginx Configuration
Create `nginx.conf`:
```nginx
events {
    worker_connections 1024;
}

http {
    upstream vaultwarden {
        server vaultwarden:80;
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    # HTTPS Server
    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        # SSL Configuration
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        # Or use Let's Encrypt:
        # ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        # ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

        # Security Headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        add_header X-XSS-Protection "1; mode=block";

        # Vaultwarden Proxy
        location / {
            proxy_pass http://vaultwarden;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # WebSocket support for notifications
        location /notifications/hub {
            proxy_pass http://vaultwarden;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        location /notifications/hub/negotiate {
            proxy_pass http://vaultwarden;
        }
    }
}
```

### 4. SSL Certificate Options

#### Option A: Let's Encrypt (Recommended)
```bash
# Install certbot
certbot certonly --standalone -d your-domain.com

# Auto-renewal
echo "0 0,12 * * * root certbot renew --quiet" | sudo tee -a /etc/crontab
```

#### Option B: Self-Signed (Testing)
```bash
# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ssl/key.pem -out ssl/cert.pem
```

### 5. Production Environment Variables
Update `.env.prod`:
```bash
# Production domain
DOMAIN=https://your-domain.com

# Strong admin token (keep from development)
ADMIN_TOKEN=your-existing-token

# Email configuration
SMTP_HOST=smtp.your-provider.com
SMTP_FROM=vaultwarden@your-domain.com
SMTP_USERNAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password

# Optional: PostgreSQL for production
# DATABASE_URL=postgresql://user:password@postgres/vaultwarden
```

### 6. Migration Commands
```bash
# Stop development containers
docker compose down

# Backup data
cp -r vw-data vw-data-backup

# Start production containers
docker compose -f docker-compose.prod.yml up -d

# Update admin settings
curl -X POST \
  -H "Authorization: Bearer YOUR-ADMIN-TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"signupsAllowed":false}' \
  https://your-domain.com/admin/config
```

### 7. Security Checklist
- [ ] Disable signups after creating your account
- [ ] Enable 2FA for your account
- [ ] Configure email for notifications
- [ ] Set up automated backups
- [ ] Configure firewall rules
- [ ] Enable fail2ban for brute force protection
- [ ] Regular security updates

### 8. Backup Strategy
```bash
#!/bin/bash
# backup.sh
DATE=$(date +%Y%m%d_%H%M%S)
tar -czf "backups/vaultwarden_$DATE.tar.gz" vw-data/
# Upload to S3 or other storage
```

## Rollback Plan
If issues occur:
1. Stop production containers: `docker compose -f docker-compose.prod.yml down`
2. Restore data: `cp -r vw-data-backup vw-data`
3. Restart development: `docker compose up -d`

## Notes
- Keep the same ADMIN_TOKEN to maintain admin access
- SQLite is fine for small deployments (<100 users)
- Consider PostgreSQL for larger deployments
- Monitor logs: `docker compose -f docker-compose.prod.yml logs -f`