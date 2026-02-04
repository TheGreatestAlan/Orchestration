# Production Agent Instructions - API Key Encryption Deployment

## Overview

The production deployment process has been updated to include API key encryption at rest. As the production agent, you need to ensure the deployment includes the required encryption configuration.

## New Requirements

### 1. API Key Encryption Key
- **Required Environment Variable**: `API_KEY_ENCRYPTION_KEY`
- **Format**: Base64-encoded string (32 bytes)
- **Location**: Must be set in production environment before deployment

### 2. Configuration Files to Update
- Production environment file: `/root/Orchestration/obsRemote/dev/docker-compose.env`
- Docker compose file: `/root/Orchestration/obsRemote/run_obsidian_remote.yml`

## Pre-Deployment Checklist

### Step 1: Verify Encryption Key
```bash
# Check if encryption key exists in production
ssh root@digitalocean "grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env"

# If not found, generate and add it
if [ $? -ne 0 ]; then
    # Generate new key
    ENCRYPTION_KEY=$(openssl rand -base64 32)

    # Add to production env file
    ssh root@digitalocean "echo 'API_KEY_ENCRYPTION_KEY=$ENCRYPTION_KEY' >> /root/Orchestration/obsRemote/dev/docker-compose.env"

    # Update docker-compose
    ssh root@digitalocean "sed -i '/open-webui:/,/networks:/ { /environment:/ { a\\      - API_KEY_ENCRYPTION_KEY=\${API_KEY_ENCRYPTION_KEY} } }' /root/Orchestration/obsRemote/run_obsidian_remote.yml"
fi
```

### Step 2: Validate Configuration
```bash
# Verify the key is properly set
ssh root@digitalocean "grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env"

# Verify docker-compose includes the environment variable
ssh root@digitalocean "grep -A10 'open-webui:' /root/Orchestration/obsRemote/run_obsidian_remote.yml | grep API_KEY_ENCRYPTION_KEY"
```

### Step 3: Test Key Format
```bash
# Get the key from production
KEY=$(ssh root@digitalocean "grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env | cut -d'=' -f2")

# Validate it's base64
if ! echo "$KEY" | base64 -d > /dev/null 2>&1; then
    echo "❌ ERROR: Invalid encryption key format"
    exit 1
fi
```

## Deployment Process Updates

### Standard Deployment
1. **Before running deployment**, ensure `API_KEY_ENCRYPTION_KEY` is set:
   ```bash
   export API_KEY_ENCRYPTION_KEY="$(ssh root@digitalocean 'grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env | cut -d"=" -f2')"
   ```

2. **Run deployment with encryption support**:
   ```bash
   cd /home/alan/workspace/flofluent-frontend
   ./scripts/deploy-with-encryption.sh patch
   ```

### Manual Deployment (if scripts fail)
1. **Set environment on production server**:
   ```bash
   ssh root@digitalocean
   cd /root/Orchestration/obsRemote
   source dev/docker-compose.env
   ```

2. **Deploy with encryption key**:
   ```bash
   OPENWEBUI_VERSION=$VERSION API_KEY_ENCRYPTION_KEY=$API_KEY_ENCRYPTION_KEY docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate open-webui
   ```

## Post-Deployment Verification

### Step 1: Container Health Check
```bash
# Check if container started successfully
ssh root@digitalocean "docker ps | grep open-webui"

# Check container logs for encryption errors
ssh root@digitalocean "docker logs open-webui 2>&1 | grep -i encryption"
```

### Step 2: Application Health Check
```bash
# Check health endpoint
curl -s https://flofluent.com/health | jq .

# Verify version matches deployment
VERSION=$(cat /home/alan/workspace/flofluent-frontend/VERSION)
curl -s https://flofluent.com/health | jq -r '.version' | grep -q "$VERSION" && echo "✅ Version matches" || echo "❌ Version mismatch"
```

### Step 3: API Key Encryption Test
```bash
# Login to the application and add a test API key
# Verify the key is encrypted in the database
ssh root@digitalocean "docker exec open-webui sqlite3 /app/backend/data/webui.db \"SELECT value FROM config WHERE key LIKE '%api_key%' LIMIT 1;\" | grep '\$encrypted\$'"
```

## Troubleshooting

### Error: "API_KEY_ENCRYPTION_KEY is not set"
- Ensure the environment variable is properly exported
- Check that it's included in the docker-compose environment section
- Verify the production env file contains the key

### Error: "Invalid encryption key format"
- Regenerate a valid base64 key: `openssl rand -base64 32`
- Update production configuration with new key

### Container fails to start
- Check docker logs: `ssh root@digitalocean "docker logs open-webui"`
- Verify all environment variables are properly set
- Ensure the encryption key is valid base64

## Security Checklist

- [ ] Encryption key is generated using secure random method
- [ ] Key is stored securely (not in version control)
- [ ] Production environment file is properly secured
- [ ] Key is different across environments (dev/staging/prod)
- [ ] Key is backed up securely
- [ ] No API keys are exposed in logs
- [ ] Encryption is working (test with new API key)

## Emergency Procedures

### Lost Encryption Key
1. **DO NOT restart the container** (it may fail to decrypt existing keys)
2. **Backup current database** immediately
3. **Generate new key** and update configuration
4. **Notify team** that existing API keys need to be re-entered

### Rollback Procedure
```bash
# Rollback to previous version
PREVIOUS_VERSION=$(ssh root@digitalocean "docker exec open-webui cat /app/version.txt 2>/dev/null || echo '0.6.42'")
ssh root@digitalocean "cd /root/Orchestration/obsRemote && OPENWEBUI_VERSION=$PREVIOUS_VERSION docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate open-webui"
```

## Important Notes

1. **Always backup the encryption key** - losing it means losing access to all encrypted API keys
2. **Test in staging first** - verify encryption works before production deployment
3. **Monitor logs** - watch for encryption-related errors after deployment
4. **Keep key secure** - never commit the key to version control or share it unnecessarily
5. **Document the key location** - ensure team knows where the key is stored

## Quick Commands Reference

```bash
# Check current encryption status
ssh root@digitalocean "grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env"

# Generate new encryption key
openssl rand -base64 32

# Update production with new key
./scripts/update-production-encryption.sh "your-new-key"

# Deploy with encryption
export API_KEY_ENCRYPTION_KEY="your-key"
./scripts/deploy-with-encryption.sh patch

# Verify deployment
ssh root@digitalocean "docker logs open-webui 2>&1 | tail -20"
curl -s https://flofluent.com/health | jq .
```

Remember: The encryption key is critical for API key security. Handle it with the same care as passwords or other sensitive credentials.