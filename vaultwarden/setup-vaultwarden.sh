#!/bin/bash

# Vaultwarden Automated Setup Script
# One-command deployment for production

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN=""
EMAIL=""
ADMIN_TOKEN=""
ENV_FILE=".env.prod"
COMPOSE_FILE="docker-compose.prod.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."

    command -v docker >/dev/null 2>&1 || error "Docker is not installed"
    command -v docker >/dev/null 2>&1 || error "Docker Compose is not installed"

    # Check if docker daemon is running
    docker ps >/dev/null 2>&1 || error "Docker daemon is not running"

    log "✅ All dependencies satisfied"
}

# Generate secure token
generate_token() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48
    else
        # Fallback to /dev/urandom
        head -c 32 /dev/urandom | base64
    fi
}

# Get user input
get_input() {
    echo ""
    echo "=== Vaultwarden Production Setup ==="
    echo ""

    # Domain
    read -p "Enter your domain (e.g., vault.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        error "Domain is required"
    fi

    # Email
    read -p "Enter admin email: " EMAIL
    if [ -z "$EMAIL" ]; then
        error "Email is required"
    fi

    # Admin token
    echo ""
    read -p "Generate admin token automatically? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ADMIN_TOKEN=$(generate_token)
        log "Generated admin token: $ADMIN_TOKEN"
        echo "IMPORTANT: Save this token! You'll need it to access the admin panel."
    else
        read -p "Enter admin token: " ADMIN_TOKEN
        if [ -z "$ADMIN_TOKEN" ]; then
            error "Admin token is required"
        fi
    fi

    echo ""
    read -p "Enable email notifications? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "SMTP Host: " SMTP_HOST
        read -p "SMTP Port (default: 587): " SMTP_PORT
        SMTP_PORT=${SMTP_PORT:-587}
        read -p "SMTP Username: " SMTP_USER
        read -p "SMTP Password: " -s SMTP_PASS
        echo
        read -p "SMTP From Address: " SMTP_FROM
    fi
}

# Create production docker-compose file
create_compose_file() {
    log "Creating production docker-compose file..."

    cat > "$SCRIPT_DIR/$COMPOSE_FILE" <<EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    expose:
      - "80"
    volumes:
      - ./vw-data:/data
    environment:
      - DOMAIN=https://${DOMAIN}
      - ADMIN_TOKEN=\${ADMIN_TOKEN}
      - SIGNUPS_ALLOWED=false
      - INVITATIONS_ALLOWED=true
      - SHOW_PASSWORD_HINT=false
      - WEB_VAULT_ENABLED=true
      - SMTP_HOST=\${SMTP_HOST:-}
      - SMTP_FROM=\${SMTP_FROM:-}
      - SMTP_PORT=\${SMTP_PORT:-587}
      - SMTP_SECURITY=starttls
      - SMTP_USERNAME=\${SMTP_USERNAME:-}
      - SMTP_PASSWORD=\${SMTP_PASSWORD:-}
      - LOG_LEVEL=info
    networks:
      - vaultwarden-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/alive"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

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

  certbot:
    image: certbot/certbot:latest
    container_name: certbot
    volumes:
      - ./letsencrypt:/etc/letsencrypt:rw
      - ./ssl:/var/www/html:rw
    command: >-
      sh -c 'while true; do
        sleep 12h &
        wait $${!}
      done'

networks:
  vaultwarden-net:
    driver: bridge

volumes:
  vw-data:
    driver: local
EOF

    log "✅ Docker compose file created"
}

# Create nginx configuration
create_nginx_config() {
    log "Creating nginx configuration..."

    cat > "$SCRIPT_DIR/nginx.conf" <<EOF
events {
    worker_connections 1024;
}

http {
    upstream vaultwarden {
        server vaultwarden:80;
    }

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=admin:10m rate=2r/s;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name ${DOMAIN};

        location /.well-known/acme-challenge/ {
            root /var/www/html;
        }

        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    # HTTPS Server
    server {
        listen 443 ssl http2;
        server_name ${DOMAIN};

        # SSL Configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/privkey.pem;
        ssl_trusted_certificate /etc/nginx/ssl/chain.pem;

        # Modern SSL configuration
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;

        # HSTS
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

        # Rate limiting
        limit_req zone=api burst=20 nodelay;

        # Vaultwarden proxy
        location / {
            proxy_pass http://vaultwarden;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }

        # Admin panel rate limiting
        location /admin {
            limit_req zone=admin burst=5 nodelay;
            proxy_pass http://vaultwarden;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }

        # WebSocket support
        location /notifications/hub {
            proxy_pass http://vaultwarden;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        location /notifications/hub/negotiate {
            proxy_pass http://vaultwarden;
        }

        # Block access to sensitive files
        location ~ /\. {
            deny all;
        }
    }
}
EOF

    log "✅ Nginx configuration created"
}

# Create environment file
create_env_file() {
    log "Creating environment file..."

    cat > "$SCRIPT_DIR/$ENV_FILE" <<EOF
# Vaultwarden Production Configuration

# Domain
DOMAIN=https://${DOMAIN}

# Admin Token
ADMIN_TOKEN=${ADMIN_TOKEN}

# Email Configuration (Optional)
SMTP_HOST=${SMTP_HOST:-}
SMTP_FROM=${SMTP_FROM:-}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USERNAME=${SMTP_USERNAME:-}
SMTP_PASSWORD=${SMTP_PASSWORD:-}

# Security Settings
SIGNUPS_ALLOWED=false
INVITATIONS_ALLOWED=true

# Performance
LOG_LEVEL=info

# Database (Optional - PostgreSQL)
# DATABASE_URL=postgresql://user:password@postgres/vaultwarden
# DATABASE_MAX_CONNS=10
EOF

    log "✅ Environment file created"
}

# Create setup script for nginx SSL
create_ssl_setup_script() {
    log "Creating SSL setup script..."

    cat > "$SCRIPT_DIR/setup-ssl.sh" <<'EOF'
#!/bin/bash

# SSL Setup Script for Let's Encrypt

domain=$1
email=$2

if [ -z "$domain" ] || [ -z "$email" ]; then
    echo "Usage: $0 <domain> <email>"
    exit 1
fi

# Stop nginx temporarily
docker compose -f docker-compose.prod.yml stop nginx

# Get certificate
docker run --rm \
  -v ./letsencrypt:/etc/letsencrypt \
  -v ./ssl:/var/www/html \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/html \
  --email "$email" \
  --agree-tos \
  --no-eff-email \
  -d "$domain"

# Create nginx SSL directory
mkdir -p ssl

# Copy certificates
cp letsencrypt/live/$domain/fullchain.pem ssl/
cp letsencrypt/live/$domain/privkey.pem ssl/
cp letsencrypt/live/$domain/chain.pem ssl/

# Start nginx
docker compose -f docker-compose.prod.yml start nginx

echo "✅ SSL certificates configured"
echo "Certificates will auto-renew via certbot container"
EOF

    chmod +x "$SCRIPT_DIR/setup-ssl.sh"
    log "✅ SSL setup script created"
}

# Create backup script
create_backup_script() {
    log "Creating backup script..."

    cat > "$SCRIPT_DIR/backup-prod.sh" <<'EOF'
#!/bin/bash

# Production backup script

BACKUP_DIR="/var/backups/vaultwarden"
DATA_DIR="./vw-data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vaultwarden_prod_${TIMESTAMP}.tar.gz"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
tar -czf "$BACKUP_DIR/$BACKUP_NAME" "$DATA_DIR" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup created: $BACKUP_DIR/$BACKUP_NAME"

    # Clean up old backups
    find "$BACKUP_DIR" -name "vaultwarden_prod_*.tar.gz" -mtime +$RETENTION_DAYS -delete

    # Optional: Upload to S3
    # aws s3 cp "$BACKUP_DIR/$BACKUP_NAME" s3://your-bucket/vaultwarden/
else
    echo "❌ Backup failed!"
    exit 1
fi
EOF

    chmod +x "$SCRIPT_DIR/backup-prod.sh"
    log "✅ Backup script created"
}

# Deploy function
deploy() {
    log "Deploying Vaultwarden..."

    # Create directories
    mkdir -p ssl letsencrypt backups logs

    # Start containers
    docker compose -f "$COMPOSE_FILE" up -d

    # Wait for containers to start
    sleep 10

    # Check if healthy
    if ./monitor.sh; then
        log "✅ Vaultwarden deployed successfully!"

        echo ""
        echo "=== Deployment Complete ==="
        echo "🌐 Web Vault: https://${DOMAIN}"
        echo "🔧 Admin Panel: https://${DOMAIN}/admin"
        echo "🔑 Admin Token: ${ADMIN_TOKEN}"
        echo ""
        echo "Next steps:"
        echo "1. Run ./setup-ssl.sh ${DOMAIN} ${EMAIL} to configure SSL"
        echo "2. Access https://${DOMAIN} and create your account"
        echo "3. Log into admin panel and disable invitations"
        echo "4. Set up automated backups: sudo cp crontab.txt /etc/cron.d/vaultwarden"
        echo ""
        echo "⚠️  Save your admin token in a secure place!"
    else
        error "Deployment failed - check logs with: docker compose -f $COMPOSE_FILE logs"
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "Vaultwarden Production Setup"
    echo "========================================="
    echo ""

    check_dependencies
    get_input

    echo ""
    log "Setting up Vaultwarden for production..."

    create_compose_file
    create_nginx_config
    create_env_file
    create_ssl_setup_script
    create_backup_script

    # Copy utility scripts
    cp "$SCRIPT_DIR/monitor.sh" "$SCRIPT_DIR/monitor-prod.sh"
    cp "$SCRIPT_DIR/restore.sh" "$SCRIPT_DIR/restore-prod.sh"

    echo ""
    read -p "Deploy now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy
    else
        log "Setup complete. Run 'docker compose -f $COMPOSE_FILE up -d' when ready to deploy."
    fi
}

# Run main function
main "$@"'