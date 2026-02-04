# Word-Translation Feature - Production Setup

**Date:** 2026-01-30
**Feature:** Google Translate word-translation (double-click on words)
**Required Action:** Add GOOGLE_TRANSLATE_API_KEY to production environment

---

## What Changed

The word-translation feature has been merged to main. It allows users to double-click on any word in a translated sentence to see a popup with the Google Translate translation.

### New Backend Component
- **File:** `backend/open_webui/routers/translation.py`
- **Endpoint:** `POST /api/v1/translate/word`
- **Requires:** `GOOGLE_TRANSLATE_API_KEY` environment variable

---

## Manual Setup Steps

### Step 1: Add API Key to Environment File

Edit the production environment file:

```bash
# SSH to production server
ssh root@digitalocean

# Edit the environment file
cd /root/Orchestration/obsRemote
nano dev/docker-compose.env
```

Add this line (replace with actual API key):
```bash
GOOGLE_TRANSLATE_API_KEY=AIzaSyDUuza5VRUV9YO-WmSHQhy-1sZ1RBDJ7V8
```

**Note:** The API key is already in the local `.env` file in the repository. You can copy it from there.

### Step 2: Update Docker Compose

Edit the docker-compose file to pass the environment variable to the container:

```bash
nano run_obsidian_remote.yml
```

Find the `open-webui` service and add the environment variable. Look for the `environment:` section and add:

```yaml
services:
  open-webui:
    # ... other config ...
    environment:
      - API_KEY_ENCRYPTION_KEY=${API_KEY_ENCRYPTION_KEY}
      - GOOGLE_TRANSLATE_API_KEY=${GOOGLE_TRANSLATE_API_KEY}  # ADD THIS LINE
      # ... other env vars ...
```

### Step 3: Verify Changes

Check that both files are updated:

```bash
# Check environment file
grep GOOGLE_TRANSLATE_API_KEY dev/docker-compose.env

# Check docker-compose file
grep -A20 'open-webui:' run_obsidian_remote.yml | grep GOOGLE_TRANSLATE
```

### Step 4: Deploy New Version

After setting up the environment variable, deploy the new version:

```bash
# From your local machine (in the flofluent-frontend repo)
./scripts/ci/deploy-to-prod.sh patch
```

This will:
1. Build and push v0.6.49
2. Deploy to production
3. The container will now have access to GOOGLE_TRANSLATE_API_KEY

### Step 5: Verify It Works

Test the feature:

```bash
# Test the API endpoint
curl -X POST https://flofluent.com/api/v1/translate/word \
  -H "Content-Type: application/json" \
  -d '{"word": "hello", "source_language": "en", "target_language": "es"}'
```

Expected response:
```json
{
  "word": "hello",
  "translation": "hola",
  "source_language": "en",
  "target_language": "es",
  "status": "success",
  "error": null
}
```

Then test in the browser:
1. Open https://flofluent.com
2. Start a conversation with translation mode enabled
3. Double-click on any word
4. Popup should appear with translation

---

## Files to Modify on Production Server

| File | Path | Change |
|------|------|--------|
| `dev/docker-compose.env` | `/root/Orchestration/obsRemote/dev/docker-compose.env` | Add GOOGLE_TRANSLATE_API_KEY |
| `run_obsidian_remote.yml` | `/root/Orchestration/obsRemote/run_obsidian_remote.yml` | Add env var to open-webui service |

---

## Getting the API Key

The API key is already configured in the local development environment:

```bash
# From local repo
grep GOOGLE_TRANSLATE_API_KEY .env
```

If you need a new key:
1. Go to https://console.cloud.google.com/apis/credentials
2. Create a new API key
3. Enable Cloud Translation API
4. Add the key to production

---

## Troubleshooting

### "GOOGLE_TRANSLATE_API_KEY not configured" error

**Cause:** Environment variable not set in production

**Fix:**
```bash
# Check if set
grep GOOGLE_TRANSLATE_API_KEY /root/Orchestration/obsRemote/dev/docker-compose.env

# If not set, add it and restart
nano /root/Orchestration/obsRemote/dev/docker-compose.env
# Add: GOOGLE_TRANSLATE_API_KEY=your-key-here

# Restart container
cd /root/Orchestration/obsRemote
docker compose -f run_obsidian_remote.yml restart open-webui
```

### Container doesn't have the env var

**Cause:** Docker compose not passing the variable

**Fix:**
```bash
# Check docker-compose has the env var
grep -A30 'open-webui:' run_obsidian_remote.yml | grep GOOGLE

# If missing, add it and redeploy
```

### Translation returns error

**Cause:** Invalid API key or API not enabled

**Fix:**
1. Verify API key is valid at https://console.cloud.google.com/apis/credentials
2. Ensure Cloud Translation API is enabled
3. Check billing is set up on Google Cloud project

---

## Summary

To enable word-translation on production:

1. ✅ Add `GOOGLE_TRANSLATE_API_KEY` to `dev/docker-compose.env`
2. ✅ Add `- GOOGLE_TRANSLATE_API_KEY=${GOOGLE_TRANSLATE_API_KEY}` to docker-compose `open-webui` service
3. ✅ Deploy v0.6.49 with `./scripts/ci/deploy-to-prod.sh patch`
4. ✅ Test the endpoint with curl
5. ✅ Test in browser by double-clicking words

---

**Questions?** Check the feature documentation:
- `docs/features/word-translation-usage.md` (in repo)
- `docs/task-log/word-translation-bridge-to-tomorrow-2026-01-28.md` (in repo)
