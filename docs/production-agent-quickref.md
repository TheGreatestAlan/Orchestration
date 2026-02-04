# Production Agent Quick Reference - API Key Encryption

## Pre-Deployment Check
```bash
# Check if encryption key exists
ssh root@digitalocean "grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env"

# If not found, update configuration
./scripts/update-production-encryption.sh
```

## Deployment Command
```bash
# Set encryption key and deploy
export API_KEY_ENCRYPTION_KEY="$(ssh root@digitalocean 'grep API_KEY_ENCRYPTION_KEY /root/Orchestration/obsRemote/dev/docker-compose.env | cut -d"=" -f2')"
./scripts/deploy-with-encryption.sh patch
```

## Post-Deployment Check
```bash
# Check container status
ssh root@digitalocean "docker ps | grep open-webui"

# Check logs for errors
ssh root@digitalocean "docker logs open-webui 2>&1 | tail -20"

# Verify health endpoint
curl -s https://flofluent.com/health | jq .
```

## Emergency Commands
```bash
# Rollback to previous version
PREV_VERSION=0.6.42
ssh root@digitalocean "cd /root/Orchestration/obsRemote && OPENWEBUI_VERSION=$PREV_VERSION docker compose -f run_obsidian_remote.yml up -d --no-deps --force-recreate open-webui"

# View recent logs
ssh root@digitalocean "docker logs open-webui --tail 50"

# Restart container
ssh root@digitalocean "cd /root/Orchestration/obsRemote && docker compose -f run_obsidian_remote.yml restart open-webui"
```

## Key Locations
- Environment file: `/root/Orchestration/obsRemote/dev/docker-compose.env`
- Docker compose: `/root/Orchestration/obsRemote/run_obsidian_remote.yml`
- Instructions: `/root/Orchestration/docs/production-agent-instructions.md`
- Logs: `docker logs open-webui`