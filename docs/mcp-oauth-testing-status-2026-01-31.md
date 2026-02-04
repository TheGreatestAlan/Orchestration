# MCP OAuth Testing Status - January 31, 2026

## Session Overview

**Date:** 2026-01-31
**Duration:** ~2 hours
**Objective:** Test OAuth 2.1 Authorization Code flow with PKCE and diagnose MCP ChatGPT integration issues
**Status:** Multiple issues identified, investigation requests sent to production agent

---

## What We Accomplished

### 1. MCP Chrome DevTools Setup ✓
- Successfully configured MCP Chrome DevTools server
- Chromium running in debug mode on port 9222
- Browser automation tools working (navigate, screenshot, snapshot, fill_form, click)
- Configuration file: `.claude/settings.local.json`

### 2. OAuth PKCE Testing - Partial Success

**Working:**
- ✓ PKCE parameter generation (proper base64url encoding)
- ✓ Authorization URL loads correctly
- ✓ Keycloak login page displays
- ✓ Authorization codes generated successfully
- ✓ OAuth redirect flow completes

**Not Working:**
- ✗ Token exchange fails with `"Code not valid"` error
- ✗ All authorization codes rejected despite being fresh (<5 seconds old)
- ✗ PKCE parameters verified correct cryptographically

### 3. ChatGPT MCP Integration Testing

**Working:**
- ✓ ChatGPT connects to `https://alanhoangnguyen.com/mcp/sse`
- ✓ OAuth authentication successful
- ✓ Connection established (HTTP 200 OK)

**Not Working:**
- ✗ Zero tools returned from MCP server
- ✗ ChatGPT shows "All tools are hidden" but no tools visible in editor
- ✗ MCP server not responding with tool list

---

## Current Blockers

### Blocker 1: OAuth Token Exchange Failure
**Error:** `{"error":"invalid_grant","error_description":"Code not valid"}`

**Impact:** Cannot obtain OAuth access tokens programmatically

**Evidence:**
- 2 separate authorization codes tested
- Both exchanged within 5 seconds of generation
- PKCE parameters verified correct (code_verifier matches code_challenge)
- Same error on both attempts

**Possible Causes:**
1. Keycloak client configuration issue
2. Redirect URI mismatch (exact string comparison)
3. Server-side code validation logic error
4. Session state validation failing

**Investigation Needed:** Keycloak server logs analysis (requested from production agent)

### Blocker 2: MCP Server Returns Zero Tools
**Error:** No error, but empty tools list

**Impact:** ChatGPT integration unusable - no tools to invoke

**Evidence:**
- Server logs show: `GET /sse HTTP/1.1" 200 OK`
- OAuth authentication successful
- Connection established but no tools discovered
- ChatGPT UI shows no tool list to unhide

**Possible Causes:**
1. MCP protocol not fully implemented
2. Tools not registered with MCP server
3. SSE transport handshake incomplete
4. tools/list method not implemented
5. OAuth scope issue preventing tool listing

**Investigation Needed:** MCP server implementation review (requested from production agent)

---

## Key Findings

### 1. PKCE Implementation Fixed
**Previous Issue:** `Invalid parameter: code_challenge`
**Root Cause:** Incorrect base64url encoding
**Solution:** Production agent provided correctly formatted PKCE parameters

**Correct Format:**
```bash
CODE_VERIFIER=$(LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
```

### 2. Test User Credentials
**Working User:** `mcp-tester-1769879674` / `McpTest2026!`
**Non-Working User:** `oauth-test` / `TestPassword123!`

Production agent created new test user after original credentials failed.

### 3. Redirect URI Change
**Original:** `http://localhost:8888/callback` (connection refused errors)
**Current:** `https://alanhoangnguyen.com/oauth-callback` (production URL)

### 4. OAuth Configuration
**Client ID:** `chatgpt-mcp-client`
**Client Secret:** `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu`
**Realm:** `mcp`
**Required Scopes:** `openid email profile`
**PKCE:** Required (S256 method)

### 5. MCP Server Details
**Endpoint:** `https://alanhoangnguyen.com/mcp/sse`
**Transport:** Server-Sent Events (SSE)
**Authentication:** OAuth 2.1 (JWT tokens)
**Container:** `obsremote-organizerserver-1`
**Expected Tools:** inventory management, notes, todos

---

## Documents Created

### 1. OAuth Test Results
**File:** `/root/Orchestration/docs/oauth-test-results-2026-01-31.md`
**Location:** Production server
**Content:** Detailed OAuth flow testing results, PKCE verification, error analysis

### 2. Initial Findings
**File:** `/root/Orchestration/docs/oauth-authorization-code-flow-testing-findings.md`
**Location:** Production server
**Content:** First round of testing showing PKCE requirement and format issues

### 3. MCP Investigation Request
**File:** `/root/Orchestration/docs/mcp-chatgpt-zero-tools-investigation.md`
**Location:** Production server
**Content:** Request for production agent to investigate why MCP server returns zero tools

### 4. Task Log
**File:** `docs/task-log/oauth-testing-mcp-chrome-setup-2026-01-31.md`
**Location:** Local repository
**Content:** Session progress log, MCP Chrome DevTools setup steps

---

## Instructions Received from Production Agent

### 1. PKCE Test Instructions
**File:** `mcp-oauth-pkce-test-instructions-2026-01-31.md`
**Content:**
- Pre-generated PKCE parameters
- Step-by-step OAuth flow testing
- Test credentials
- Troubleshooting guide

### 2. Local Test Instructions
**File:** `mcp-oauth-local-test-2026-01-31.md`
**Content:**
- Bash script for local OAuth testing
- Manual testing alternative
- Focus on speed (60-second code expiration)

---

## Tools & Configuration

### MCP Chrome DevTools
**Server Command:** `npx chrome-devtools-mcp@latest`
**Browser:** Chromium debug mode, port 9222
**Config:** `.claude/settings.local.json`

**Tools Available:**
- `mcp__chrome-devtools__navigate_page`
- `mcp__chrome-devtools__take_screenshot`
- `mcp__chrome-devtools__take_snapshot`
- `mcp__chrome-devtools__fill_form`
- `mcp__chrome-devtools__click`
- `mcp__chrome-devtools__evaluate_script`
- 12+ other browser automation tools

### OAuth Testing Scripts
**PKCE Generator:** `/tmp/oauth_session.txt` (current session parameters)
**Token Exchange:** `/tmp/exchange-code.sh` (reusable script)

---

## Next Steps

### Immediate (After Context Clear)

1. **Complete OAuth Token Test**
   - Generate fresh PKCE parameters
   - Use MCP Chrome DevTools to automate login
   - Capture authorization code
   - Exchange for token
   - Test MCP server `/sse` endpoint with valid token

2. **Test MCP Protocol**
   - Connect to `/mcp/sse` with OAuth token
   - Send MCP `initialize` request
   - Send `tools/list` request
   - Document what server returns

3. **Compare Expected vs Actual**
   - Expected: List of inventory/notes/todo tools
   - Actual: (TBD based on testing)

### Dependent on Production Agent

1. **Keycloak Investigation**
   - Why are authorization codes rejected?
   - Check server logs during token exchange
   - Verify client configuration

2. **MCP Implementation Review**
   - Is MCP protocol implemented?
   - Are tools registered?
   - Is `tools/list` method working?
   - Review SSE transport implementation

---

## Commands for Quick Restart

### Generate Fresh OAuth Session
```bash
CODE_VERIFIER=$(LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
STATE="test-$(date +%s)"

echo "CODE_VERIFIER=$CODE_VERIFIER" > /tmp/oauth_session.txt
echo "CODE_CHALLENGE=$CODE_CHALLENGE" >> /tmp/oauth_session.txt
echo "STATE=$STATE" >> /tmp/oauth_session.txt

# Authorization URL
echo "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=https://alanhoangnguyen.com/oauth-callback&response_type=code&scope=openid%20email%20profile&state=$STATE&code_challenge=$CODE_CHALLENGE&code_challenge_method=S256"
```

### Automated Login with MCP Chrome DevTools
```javascript
// Navigate to auth URL
window.location.href = "AUTH_URL_HERE";

// After redirect, extract code
const match = window.location.href.match(/code=([^&]+)/);
return match ? match[1] : null;
```

### Exchange Code for Token
```bash
source /tmp/oauth_session.txt

curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=CODE_HERE" \
    -d "redirect_uri=https://alanhoangnguyen.com/oauth-callback" \
    -d "code_verifier=$CODE_VERIFIER" | python3 -m json.tool
```

### Test MCP Endpoint
```bash
timeout 10 curl -N https://alanhoangnguyen.com/mcp/sse \
    -H "Authorization: Bearer $ACCESS_TOKEN"
```

---

## Reference URLs

- **Keycloak Admin:** https://auth.alanhoangnguyen.com/admin
- **MCP SSE Endpoint:** https://alanhoangnguyen.com/mcp/sse
- **OAuth Callback:** https://alanhoangnguyen.com/oauth-callback
- **Production Server:** root@digitalocean

---

## Known Issues

1. **"Code not valid" on token exchange** - BLOCKING
2. **MCP server returns zero tools** - BLOCKING
3. **oauth-test user credentials don't work** - RESOLVED (new user created)
4. **localhost callback causes connection refused** - RESOLVED (using production URL)
5. **PKCE format errors** - RESOLVED (correct format provided)

---

## Success Criteria (Not Yet Met)

- [ ] Successfully exchange authorization code for access token
- [ ] Obtain valid JWT token with required scopes
- [ ] Connect to MCP SSE endpoint with token
- [ ] Receive list of tools from MCP server
- [ ] Invoke at least one MCP tool successfully
- [ ] ChatGPT shows available tools in connector UI

---

## Environment Details

**Local Machine:**
- OS: Linux 6.14.0-37-generic
- Working Directory: `/home/alan/workspace/OrganizerServer/organizerserver`
- Chromium Debug Port: 9222

**Production Server:**
- Host: root@digitalocean
- Container: obsremote-organizerserver-1
- Keycloak Realm: mcp
- OAuth Issuer: https://auth.alanhoangnguyen.com/realms/mcp

**Git Status:**
- Branch: master
- Recent Changes: MCP OAuth config added
- Version: 0.1.2

---

## Contact Points

**Local Agent (this session):** Testing OAuth flow, browser automation, MCP client testing
**Production Agent:** Server configuration, Keycloak setup, MCP implementation

**Handoff Documents Location:** `/root/Orchestration/docs/` on production server

---

**Last Updated:** 2026-01-31 17:55 UTC
**Status:** Ready for next testing session after context clear
