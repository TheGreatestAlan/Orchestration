# 🚀 Quick Start for Tomorrow

## What You Need to Do

**Goal:** Test that the MCP OAuth flow works with the new scopes (`openid,email,profile`)

---

## Step 1: Open This URL in Browser

```
https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-123
```

---

## Step 2: Login

**Username:** `oauth-test`
**Password:** `TestPassword123!`

(If this doesn't work, see "Alternative: Create New User" below)

---

## Step 3: Copy the Redirect URL

After login, you'll be redirected to a URL like:
```
http://localhost:8888/callback?code=AbCdEf123456...&state=test-123
```

Browser will show "connection refused" - **this is normal!**

**Copy the entire URL** from your browser's address bar.

---

## Step 4: Exchange Code for Token

Replace `YOUR_CODE_HERE` with the code from the URL:

```bash
curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=YOUR_CODE_HERE" \
    -d "redirect_uri=http://localhost:8888/callback" | python3 -m json.tool
```

You should get a response with `access_token`. Copy the token value.

---

## Step 5: Test MCP Endpoint

Replace `YOUR_TOKEN_HERE` with the access token:

```bash
# Test the endpoint
timeout 3 curl -v \
    -H "Authorization: Bearer YOUR_TOKEN_HERE" \
    https://alanhoangnguyen.com/mcp/sse

# Check if JWT validator accepted it
docker logs jwt_validator --tail 10
```

---

## ✅ Success Looks Like

- Token exchange returns JSON with `access_token`, `scope: "openid email profile"`
- MCP endpoint returns HTTP 200
- JWT validator logs show: `INFO: Token validated successfully for subject: ...`

---

## ❌ If Something Fails

### Login doesn't work?

**Create a new user:**
```bash
cd /root/Orchestration/obsRemote
docker exec keycloak /opt/keycloak/bin/kcadm.sh create users -r mcp \
  -s username=test-$(date +%s) \
  -s enabled=true \
  -s emailVerified=true

# Set password (replace username with the one created above)
docker exec keycloak /opt/keycloak/bin/kcadm.sh set-password -r mcp \
  --username test-XXXXX \
  --new-password TestPassword123!
```

### Token exchange fails?

- Check the authorization code wasn't already used (they're one-time use)
- Go back to Step 1 and get a fresh code
- Make sure you copy the FULL redirect URL including the code

### MCP endpoint returns 401?

- Check JWT validator logs: `docker logs jwt_validator --tail 20`
- Verify required scopes: Should show `INFO: Required scopes: [openid email profile]`
- If it shows empty `[]`, recreate the container:
  ```bash
  cd /root/Orchestration/obsRemote
  source script/sourceEnv.sh
  docker compose -f run_obsidian_remote.yml up -d --force-recreate --no-deps jwt-validator
  ```

---

## 📖 Full Documentation

See `mcp-oauth-scope-change-bridge-2026-01-31.md` in this directory for complete details.

---

**Quick Status Check:**
```bash
# Is jwt-validator running with correct config?
docker logs jwt_validator --tail 5 | grep "Required scopes"
# Should show: INFO: Required scopes: [openid email profile]

# What changed?
cd /root/Orchestration/obsRemote
git diff run_obsidian_remote.yml
# Should show: - REQUIRED_SCOPES= → - REQUIRED_SCOPES=openid,email,profile
```
