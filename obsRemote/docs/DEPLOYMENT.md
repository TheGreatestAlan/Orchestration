# Container Deployment Guide

This document describes how to deploy container updates to the production server via SSH.

## Prerequisites

### SSH Access
- SSH key authorized on the production server
- Access to `root@<server-ip>` or appropriate user with Docker permissions
- Server: Located at the IP where `registry.alanhoangnguyen.com` resolves

### Required Information
- Container image name (e.g., `agent-server`, `conversationalist`, `openwebui-monolithic`)
- New version tag (e.g., `1.0.36`, `0.6.7`)
- Service name in docker-compose (e.g., `agent-server`, `translator`, `open-webui`)

## Deployment Architecture

### Version Persistence

Container versions are persisted in `/root/Orchestration/obsRemote/dev/docker-compose.env`:

```bash
# Container Versions (updated by deploy script)
AGENT_VERSION=1.0.35
OPENWEBUI_VERSION=0.6.6
TRANSLATOR_VERSION=1.0.6
```

These environment variables are referenced in `run_obsidian_remote.yml`:

```yaml
agent-server:
  image: registry.alanhoangnguyen.com/admin/agent-server:${AGENT_VERSION:-latest}

translator:
  image: registry.alanhoangnguyen.com/admin/conversationalist:${TRANSLATOR_VERSION:-latest}

open-webui:
  image: registry.alanhoangnguyen.com/admin/openwebui-monolithic:${OPENWEBUI_VERSION:-latest}
```

**CRITICAL**: The env file ensures that if the instance restarts, it will pull the correct versioned images, not just `:latest`.

### Private Registry

All custom images are hosted at: `registry.alanhoangnguyen.com/admin/`

Available repositories:
- `admin/agent-server` - Main AI agent service
- `admin/conversationalist` - Translation service (deployed as `translator`)
- `admin/openwebui-monolithic` - Web UI (deployed as `open-webui`)
- `admin/worker` - Background worker (not currently deployed)

## Deployment Methods

### Method 1: Automated Deployment Script (Recommended)

Create a deployment script that handles the entire process:

```bash
#!/bin/bash
# deploy.sh - Deploy a specific container version

set -e

# Configuration
SERVER_USER="root"
SERVER_HOST="your-server-ip"
ORCHESTRATION_PATH="/root/Orchestration/obsRemote"

# Arguments
SERVICE_NAME=$1        # e.g., "agent-server"
IMAGE_NAME=$2          # e.g., "agent-server" (registry path)
VERSION=$3             # e.g., "1.0.36"
ENV_VAR_NAME=$4        # e.g., "AGENT_VERSION"

if [ -z "$SERVICE_NAME" ] || [ -z "$IMAGE_NAME" ] || [ -z "$VERSION" ] || [ -z "$ENV_VAR_NAME" ]; then
    echo "Usage: $0 <service-name> <image-name> <version> <env-var-name>"
    echo "Example: $0 agent-server agent-server 1.0.36 AGENT_VERSION"
    exit 1
fi

echo "Deploying ${SERVICE_NAME} version ${VERSION}..."

# SSH into server and deploy
ssh ${SERVER_USER}@${SERVER_HOST} << EOF
set -e

cd ${ORCHESTRATION_PATH}

# Backup current env file
cp dev/docker-compose.env dev/docker-compose.env.backup-\$(date +%Y%m%d_%H%M%S)

# Update version in env file
sed -i "s/^${ENV_VAR_NAME}=.*/${ENV_VAR_NAME}=${VERSION}/" dev/docker-compose.env

# Verify the change
echo "Updated ${ENV_VAR_NAME} to:"
grep "^${ENV_VAR_NAME}=" dev/docker-compose.env

# Source environment
source script/sourceEnv.sh

# Pull the new image
echo "Pulling registry.alanhoangnguyen.com/admin/${IMAGE_NAME}:${VERSION}..."
docker pull registry.alanhoangnguyen.com/admin/${IMAGE_NAME}:${VERSION}

# Update the service (no-deps ensures only this service is recreated)
echo "Updating ${SERVICE_NAME}..."
docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate ${SERVICE_NAME}

# Check service status
echo "Service status:"
docker compose -f run_obsidian_remote.yml ps ${SERVICE_NAME}

# Show recent logs
echo "Recent logs:"
docker compose -f run_obsidian_remote.yml logs --tail=50 ${SERVICE_NAME}

echo "Deployment complete!"
EOF

echo "✅ ${SERVICE_NAME} deployed successfully to version ${VERSION}"
```

**Usage:**
```bash
# Deploy agent-server
./deploy.sh agent-server agent-server 1.0.36 AGENT_VERSION

# Deploy translator (conversationalist)
./deploy.sh translator conversationalist 1.0.7 TRANSLATOR_VERSION

# Deploy open-webui
./deploy.sh open-webui openwebui-monolithic 0.6.7 OPENWEBUI_VERSION
```

### Method 2: Manual SSH Deployment

For manual deployments, follow these steps:

```bash
# 1. SSH into the server
ssh root@your-server-ip

# 2. Navigate to the orchestration directory
cd /root/Orchestration/obsRemote

# 3. Backup the environment file
cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)

# 4. Edit the environment file to update the version
nano dev/docker-compose.env
# Change: AGENT_VERSION=1.0.35
# To:     AGENT_VERSION=1.0.36

# 5. Source the environment
source script/sourceEnv.sh

# 6. Pull the new image
docker pull registry.alanhoangnguyen.com/admin/agent-server:1.0.36

# 7. Update the service
docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate agent-server

# 8. Verify deployment
docker compose -f run_obsidian_remote.yml ps agent-server
docker compose -f run_obsidian_remote.yml logs --tail=50 agent-server

# 9. Exit SSH session
exit
```

### Method 3: Using the Existing Windows Script

There's a Windows batch script available at `script/updateServiceWithSetEnv.bat`:

```batch
# From Windows machine with Docker context set to remote server
cd C:\path\to\Orchestration\obsRemote\script
updateServiceWithSetEnv.bat agent-server
```

**Note:** This script pulls `:latest` tag, so you'd need to update the env file manually first.

## Service-Specific Deployment Commands

### Agent Server
```bash
./deploy.sh agent-server agent-server 1.0.36 AGENT_VERSION
```

### Translator (Conversationalist)
```bash
./deploy.sh translator conversationalist 1.0.7 TRANSLATOR_VERSION
```

### Open WebUI
```bash
./deploy.sh open-webui openwebui-monolithic 0.6.7 OPENWEBUI_VERSION
```

## CI/CD Integration Examples

### GitHub Actions

```yaml
name: Deploy to Production

on:
  workflow_dispatch:
    inputs:
      service:
        description: 'Service to deploy'
        required: true
        type: choice
        options:
          - agent-server
          - translator
          - open-webui
      version:
        description: 'Version to deploy'
        required: true
        type: string

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H ${{ secrets.SERVER_IP }} >> ~/.ssh/known_hosts

      - name: Deploy
        run: |
          # Map service to image and env var
          case "${{ inputs.service }}" in
            agent-server)
              IMAGE="agent-server"
              ENV_VAR="AGENT_VERSION"
              ;;
            translator)
              IMAGE="conversationalist"
              ENV_VAR="TRANSLATOR_VERSION"
              ;;
            open-webui)
              IMAGE="openwebui-monolithic"
              ENV_VAR="OPENWEBUI_VERSION"
              ;;
          esac

          ssh root@${{ secrets.SERVER_IP }} << 'EOF'
            cd /root/Orchestration/obsRemote
            cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)
            sed -i "s/^${ENV_VAR}=.*/${ENV_VAR}=${{ inputs.version }}/" dev/docker-compose.env
            source script/sourceEnv.sh
            docker pull registry.alanhoangnguyen.com/admin/${IMAGE}:${{ inputs.version }}
            docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate ${{ inputs.service }}
            docker compose -f run_obsidian_remote.yml logs --tail=50 ${{ inputs.service }}
          EOF
```

### GitLab CI

```yaml
deploy:
  stage: deploy
  only:
    - tags
  script:
    - eval $(ssh-agent -s)
    - echo "$DEPLOY_SSH_KEY" | ssh-add -
    - ssh root@$SERVER_IP << 'EOF'
        cd /root/Orchestration/obsRemote
        cp dev/docker-compose.env dev/docker-compose.env.backup-$(date +%Y%m%d_%H%M%S)
        sed -i "s/^AGENT_VERSION=.*/AGENT_VERSION=${CI_COMMIT_TAG}/" dev/docker-compose.env
        source script/sourceEnv.sh
        docker pull registry.alanhoangnguyen.com/admin/agent-server:${CI_COMMIT_TAG}
        docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate agent-server
      EOF
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any

    parameters {
        choice(name: 'SERVICE', choices: ['agent-server', 'translator', 'open-webui'], description: 'Service to deploy')
        string(name: 'VERSION', description: 'Version to deploy')
    }

    stages {
        stage('Deploy') {
            steps {
                script {
                    def imageMap = [
                        'agent-server': ['image': 'agent-server', 'var': 'AGENT_VERSION'],
                        'translator': ['image': 'conversationalist', 'var': 'TRANSLATOR_VERSION'],
                        'open-webui': ['image': 'openwebui-monolithic', 'var': 'OPENWEBUI_VERSION']
                    ]

                    def config = imageMap[params.SERVICE]

                    sshagent(['production-server-key']) {
                        sh """
                            ssh root@\${SERVER_IP} << 'EOF'
                                cd /root/Orchestration/obsRemote
                                cp dev/docker-compose.env dev/docker-compose.env.backup-\$(date +%Y%m%d_%H%M%S)
                                sed -i "s/^${config.var}=.*/${config.var}=${params.VERSION}/" dev/docker-compose.env
                                source script/sourceEnv.sh
                                docker pull registry.alanhoangnguyen.com/admin/${config.image}:${params.VERSION}
                                docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate ${params.SERVICE}
                                docker compose -f run_obsidian_remote.yml ps ${params.SERVICE}
                            EOF
                        """
                    }
                }
            }
        }
    }
}
```

## Post-Deployment Verification

After deploying, verify the deployment:

```bash
# Check service is running
ssh root@server "cd /root/Orchestration/obsRemote && docker compose -f run_obsidian_remote.yml ps"

# Check service health
ssh root@server "docker ps | grep <service-name>"

# View logs
ssh root@server "cd /root/Orchestration/obsRemote && ./script/see-logs.sh -t <service-name>"

# Verify version in env file
ssh root@server "grep VERSION /root/Orchestration/obsRemote/dev/docker-compose.env"
```

## Rollback Procedure

If a deployment fails, rollback to the previous version:

```bash
ssh root@server << 'EOF'
cd /root/Orchestration/obsRemote

# Find the most recent backup
BACKUP=$(ls -t dev/docker-compose.env.backup-* | head -1)
echo "Rolling back to: $BACKUP"

# Restore backup
cp $BACKUP dev/docker-compose.env

# Redeploy with old version
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate agent-server

echo "Rollback complete"
EOF
```

## Troubleshooting

### Image Pull Fails

**Symptom:** `Error pulling image registry.alanhoangnguyen.com/admin/...`

**Solutions:**
1. Verify image exists in registry:
   ```bash
   ssh root@server "ls /root/Orchestration/obsRemote/registry/data/docker/registry/v2/repositories/admin/<image-name>/_manifests/tags/"
   ```

2. Check registry is running:
   ```bash
   ssh root@server "docker ps | grep registry"
   ```

3. Verify docker can reach registry:
   ```bash
   ssh root@server "curl -k https://registry.alanhoangnguyen.com/v2/"
   ```

### Service Won't Start

**Symptom:** Container exits immediately after deployment

**Solutions:**
1. Check logs:
   ```bash
   ssh root@server "cd /root/Orchestration/obsRemote && ./script/see-logs.sh <service-name>"
   ```

2. Check environment variables:
   ```bash
   ssh root@server "cd /root/Orchestration/obsRemote && source script/sourceEnv.sh && env | grep VERSION"
   ```

3. Verify volumes exist:
   ```bash
   ssh root@server "ls -la /root/Orchestration/obsRemote/<service-name>/"
   ```

### Version Not Updating

**Symptom:** Service still running old version after deployment

**Solutions:**
1. Check env file was actually updated:
   ```bash
   ssh root@server "cat /root/Orchestration/obsRemote/dev/docker-compose.env | grep VERSION"
   ```

2. Ensure `--force-recreate` flag was used:
   ```bash
   docker compose up -d --no-deps --force-recreate <service>
   ```

3. Check image digest:
   ```bash
   docker image inspect registry.alanhoangnguyen.com/admin/<image>:<version> | grep Id
   ```

## Security Considerations

### SSH Keys
- Use dedicated deployment keys (not personal keys)
- Restrict key to specific commands if possible using `authorized_keys` restrictions
- Rotate keys periodically

### Environment File
- The `dev/docker-compose.env` file contains secrets
- Ensure it's never committed to git (already in `.gitignore`)
- Backups contain secrets - manage carefully
- Consider encrypting backups at rest

### Registry Authentication
- Registry requires HTTP basic auth
- Credentials in `/root/Orchestration/obsRemote/registry/auth/htpasswd`
- Change default credentials from `admin:password`

## Best Practices

1. **Always backup** - The env file is critical for version persistence
2. **Test in staging** - If possible, test deployments in a staging environment first
3. **Monitor logs** - Watch logs during and after deployment
4. **Deploy one service at a time** - Use `--no-deps` to avoid cascading restarts
5. **Version everything** - Tag all images with semantic versions, not just `:latest`
6. **Document changes** - Keep a deployment log in `docs/task-log/`
7. **Health checks** - Implement health endpoints in services for automated verification
8. **Gradual rollout** - For critical services, consider blue-green or canary deployments

## Quick Reference

### Service to Image Mapping

| Service Name | Image Repository | Env Variable |
|-------------|------------------|--------------|
| `agent-server` | `registry.alanhoangnguyen.com/admin/agent-server` | `AGENT_VERSION` |
| `translator` | `registry.alanhoangnguyen.com/admin/conversationalist` | `TRANSLATOR_VERSION` |
| `open-webui` | `registry.alanhoangnguyen.com/admin/openwebui-monolithic` | `OPENWEBUI_VERSION` |

### Common Commands

```bash
# View current versions
ssh root@server "grep VERSION /root/Orchestration/obsRemote/dev/docker-compose.env"

# Check running services
ssh root@server "cd /root/Orchestration/obsRemote && docker compose -f run_obsidian_remote.yml ps"

# View logs
ssh root@server "cd /root/Orchestration/obsRemote && ./script/see-logs.sh -t <service>"

# Shell into container
ssh root@server "cd /root/Orchestration/obsRemote && ./script/shell-into.sh <service> bash"

# Restart service without changing version
ssh root@server "cd /root/Orchestration/obsRemote && source script/sourceEnv.sh && docker compose -f run_obsidian_remote.yml restart <service>"
```
