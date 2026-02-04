# Helper Frontend Deployment Guide

## Architecture Overview

The current production architecture consists of:

- **web**: Main web interface (port 8080)
- **organizerserver**: Obsidian vault organizer service
- **updater**: Git-based updater service

The Helper Frontend is a new component that provides an AI-assisted development interface based on Open WebUI v0.6.5.

## Deployment Steps

### 1. Build Helper Frontend Container

```bash
# On build machine
cd /home/alan/workspace/helper-frontend

# Option A: Build production-optimized container (recommended - 512MB)
# This creates a minimal nginx-based container with just the built frontend
docker build -f Dockerfile.prod -t helper-frontend:prod .
docker tag helper-frontend:prod registry.alanhoangnguyen.com/admin/helper-frontend:prod-latest
docker push registry.alanhoangnguyen.com/admin/helper-frontend:prod-latest

# Option B: Build full container (if needed for development - 21GB)
# This includes the full backend with Python dependencies
docker build -t helper-frontend:latest .
docker tag helper-frontend:latest registry.alanhoangnguyen.com/admin/helper-frontend:latest
docker push registry.alanhoangnguyen.com/admin/helper-frontend:latest
```

### 2. Update docker-compose.yml

Add the helper-frontend service to `/root/Orchestration/docker-compose.yml`:

```yaml
services:
  # ... existing services ...

  helper-frontend:
    image: registry.alanhoangnguyen.com/admin/helper-frontend:prod-latest
    ports:
      - '${HELPER_FRONTEND_PORT}:80'
    environment:
      - WEBUI_API_BASE_URL=http://helper-backend:8080  # Adjust to your backend URL
    volumes:
      - helper_frontend_data:/usr/share/nginx/html/data  # For any persistent data
    depends_on:
      - web
    restart: unless-stopped

volumes:
  helper_frontend_data:
```

### 3. Update Environment Variables

Add to the `.env` file in `/root/Orchestration/`:

```bash
# Helper Frontend Configuration
HELPER_FRONTEND_PORT=5179
```

### 4. Deploy to Production

```bash
# On production server (root@digitalocean)
cd /root/Orchestration

# Pull the new image
docker-compose pull helper-frontend

# Start the new service
docker-compose up -d helper-frontend

# Verify it's running
docker-compose ps
```

### 5. Configure Nginx Reverse Proxy

Add a new location block to the nginx configuration:

```nginx
# In /etc/nginx/sites-available/default or appropriate config
location /helper {
    proxy_pass http://localhost:5179;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;
}
```

Then reload nginx:

```bash
nginx -t && nginx -s reload
```

### 6. Verification

Check that the service is accessible:

```bash
# Test locally
curl http://localhost:5179

# Test through nginx (if configured)
curl https://helper.alanhoangnguyen.com/helper
```

## Container Registry Management

To get the container up in the registry:

1. Ensure Docker registry is running:

```bash
docker ps | grep registry
```

2. If not running, start it:

```bash
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

3. Push the image:

```bash
docker push registry.alanhoangnguyen.com/admin/helper-frontend:latest
```

## Integration Notes

- The Helper Frontend runs on port 80 in the production container (mapped to 5179 on host)
- Production image is optimized to 512MB (vs 21GB for full image)
- The production container uses nginx to serve static files
- It connects to the Helper LLM backend (already running)
- Authentication is disabled for development use
- CORS is configured to allow all origins (adjust for production)
- Data is persisted in a Docker volume for user sessions and settings

## Production Optimization

The production Dockerfile (Dockerfile.prod) creates a minimal container that:
- Only includes the built frontend files
- Uses nginx-alpine as the base image
- Includes proper security headers
- Has gzip compression enabled
- Includes health check endpoint
- Is ~40x smaller than the full container (512MB vs 21GB)

## Troubleshooting

If the container fails to start:

1. Check logs: `docker-compose logs helper-frontend`
2. Verify port availability: `netstat -tlnp | grep 5179`
3. Check image exists: `docker images | grep helper-frontend`
4. Verify registry access: `curl registry.alanhoangnguyen.com/v2/_catalog`
