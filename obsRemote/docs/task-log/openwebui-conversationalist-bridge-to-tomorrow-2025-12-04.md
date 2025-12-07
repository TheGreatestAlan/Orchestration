# OpenWebUI ↔ Conversationalist Integration – Bridge to Tomorrow

## Where we are

### Problem Identified
- User reported: "Failed to get a response from the language learning service"
- Root cause identified: **Service naming mismatch** + **API incompatibility**

### What We Fixed Today
1. ✅ **Service Renaming**: Changed `translator` → `conversationalist` in docker-compose
   - Updated `run_obsidian_remote.yml` service name from `translator` to `conversationalist`
   - Updated OpenWebUI environment variable: `OLLAMA_BASE_URL=http://conversationalist:8080`
   - Recreated containers to apply changes
   - Removed orphaned `obsremote-translator-1` container
   - Network connectivity now working: conversationalist at 172.18.0.13, open-webui at 172.18.0.3

2. ✅ **Verified Service Health**
   - conversationalist: Running, healthy, serving on 0.0.0.0:8080
   - open-webui: Running, healthy, version 0.6.5
   - Basic connectivity test passed: `curl http://conversationalist:8080/health` → 200 OK

### Current State of Services

**conversationalist (v1.0.6)**
- Image: `registry.alanhoangnguyen.com/admin/conversationalist:1.0.6`
- Built: 2025-11-25
- API: Fireworks AI-based language learning service
- Endpoints:
  - `GET /health` → Returns version info
  - `GET /api/version` → Returns 0.4.0
  - `POST /api/chat` → Custom API format (NOT Ollama-compatible)

**open-webui (v0.6.5)**
- Image: `registry.alanhoangnguyen.com/admin/openwebui-monolithic:0.6.7`
- Configured: `OLLAMA_BASE_URL=http://conversationalist:8080`
- Expects: Ollama API format
- Issue: Database migration error (non-fatal): `Can't locate revision identified by '9f0c9cd09105'`

## The Actual Problem: API Incompatibility

**OpenWebUI expects Ollama API:**
```
GET /api/tags          → List available models
POST /api/generate     → Generate completion
POST /api/chat         → Chat completion (Ollama format)
```

**Conversationalist provides Custom API:**
```json
POST /api/chat
{
  "messages": [{"role": "user", "content": "..."}],
  "source_language": "english",
  "target_language": "spanish",
  "translation_mode": false,
  "stream": true
}
```

**Key Differences:**
1. **Model discovery**: OpenWebUI calls `/api/tags` to list models → conversationalist doesn't implement this
2. **Request format**: Different JSON schemas
3. **Response format**: Different streaming/non-streaming formats
4. **Purpose**: Ollama is general LLM, conversationalist is language learning specific

## Evidence from Logs

**conversationalist logs show:**
- Started successfully at 15:43:03
- Only 1 request received: `GET /health` from open-webui (172.18.0.3)
- **Zero chat requests** despite user attempting to chat

**open-webui logs show:**
- User logged in successfully: alan.hoang.nguyen@gmail.com
- Called `/api/models` endpoint (internal)
- No attempts to reach conversationalist for chat
- Likely failing silently at model discovery phase

## Likely root causes to verify

### 1. **Missing Ollama API Implementation in Conversationalist**
The conversationalist service was likely updated to remove Ollama compatibility (based on finding `translator_rest_app.py` with Ollama proxy code in the container, but `translator_fireworks_rest_app.py` is actually running).

**Evidence:**
- `/app/conversationalist/translator_rest_app.py` exists with Ollama proxy code
- `/app/conversationalist/translator_fireworks_rest_app.py` is actually running (per entrypoint.sh)
- The Fireworks version has no Ollama endpoints

### 2. **OpenWebUI Monolithic Build Missing Custom Integration**
The `openwebui-monolithic:0.6.7` image may need special code to:
- Directly call conversationalist's custom API
- Skip model discovery for language learning mode
- Handle the custom request/response format

### 3. **Configuration Missing**
There may be environment variables or config needed to tell OpenWebUI:
- "Use conversationalist API instead of Ollama"
- "Enable language learning mode"
- "Skip model enumeration"

## Concrete next steps (tomorrow)

### Step 1: Investigate the openwebui-monolithic image
```bash
# Check if there's custom code for conversationalist integration
docker exec obsremote-open-webui-1 find /app -name "*.py" | xargs grep -l "conversationalist\|language.*learning" 2>/dev/null

# Look for custom routers or API clients
docker exec obsremote-open-webui-1 ls -la /app/backend/open_webui/routers/

# Check for custom environment variables in the running container
docker exec obsremote-open-webui-1 env | grep -E "(LANGUAGE|LEARNING|CONVERS|CUSTOM)"
```

### Step 2: Check if conversationalist needs Ollama compatibility layer
```bash
# Verify which app is configured to run
docker exec obsremote-conversationalist-1 cat /app/entrypoint.sh

# Check if there's a way to switch modes
docker exec obsremote-conversationalist-1 env | grep DEPLOYMENT_MODE

# See if translator_rest_app (Ollama proxy) can be enabled
# If so, test with DEPLOYMENT_MODE=flask
```

### Step 3: Test conversationalist API directly
```bash
# Test the actual language learning API
curl -X POST http://conversationalist:8080/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello"}],
    "source_language": "english",
    "target_language": "spanish",
    "stream": false
  }'
```

### Step 4: Check version alignment
```bash
# Check if image versions are compatible
# CONVERSATIONALIST_VERSION=1.0.6
# OPENWEBUI_VERSION=0.6.7

# Look for git history or changelogs
cd /root/Orchestration && git log --oneline --grep="conversationalist\|openwebui" -20
```

### Step 5: Add Ollama compatibility to conversationalist (if needed)

**Option A: Enable existing Ollama proxy**
If `translator_rest_app.py` can be enabled, it proxies to `localhost:11434`. Would need to:
1. Run Ollama inside the container OR
2. Point it to external Ollama OR
3. Modify it to proxy to the Fireworks API

**Option B: Add Ollama endpoints to Fireworks app**
Modify `/app/conversationalist/translator_fireworks_rest_app.py` to add:
```python
@app.route('/api/tags', methods=['GET'])
def get_tags():
    return jsonify({
        "models": [{
            "name": "language-learning",
            "modified_at": "2025-11-25T15:00:00Z"
        }]
    })

@app.route('/api/generate', methods=['POST'])
def generate():
    # Adapt request format to conversationalist format
    # Call existing chat endpoint
    # Adapt response format to Ollama format
```

**Option C: Create adapter service**
New service that sits between OpenWebUI and conversationalist:
```yaml
api-adapter:
  image: custom/ollama-conversationalist-adapter:latest
  # Translates Ollama API → conversationalist API
```

### Step 6: Fix database migration issue (lower priority)
The migration error is non-fatal but should be fixed:
```bash
# Backup database
cp dev/open-webui/webui.db dev/open-webui/webui.db.backup-$(date +%Y%m%d)

# Check migration state
docker exec obsremote-open-webui-1 alembic -c /app/backend/alembic.ini current

# May need to reset migrations or use newer image
```

## Out of scope (deferred to future tasks)

- SSL certificate renewal (working automatically)
- Adding missing environment variables (SERVERURL, INTERNAL_SUBNET - warnings only)
- Nginx configuration updates
- Investigating other 404 errors from old frontend JS files

## Notes

### Service Architecture
- All services on `obsremote_obsidian_network` Docker bridge
- Services reference each other by service name (Docker DNS)
- conversationalist uses Fireworks AI API (requires `FIREWORKS_API_KEY`)

### Key Files
- `/root/Orchestration/obsRemote/run_obsidian_remote.yml` - Docker Compose config
- `/root/Orchestration/obsRemote/dev/docker-compose.env` - Environment variables (source of truth)
- `/root/Orchestration/obsRemote/run_obsidian_remote.yml.backup-*` - Backup created before changes

### Changes Made to Git
```diff
- translator: (old service name)
+ conversationalist: (new service name)
- OLLAMA_BASE_URL=http://translator:8080
+ OLLAMA_BASE_URL=http://conversationalist:8080
```
Status: Modified, not committed

### Important Context
The user sees: **"Failed to get a response from the language learning service"**

This is likely a frontend error message, which means:
1. OpenWebUI's frontend has language learning mode
2. It's specifically looking for a "language learning service"
3. The error is probably hardcoded in openwebui-monolithic's custom code
4. This strongly suggests openwebui-monolithic was built with conversationalist integration

**Next session should focus on:** Finding the custom integration code in openwebui-monolithic and fixing/enabling it.
