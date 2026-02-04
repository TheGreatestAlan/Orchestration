# MCP OAuth PKCE Flow Test Instructions

**Date:** 2026-01-31
**Purpose:** Test OAuth 2.1 Authorization Code flow with PKCE for ChatGPT MCP integration

---

## Prerequisites

- Browser with developer tools
- Terminal access for token exchange
- Test credentials (provided below)

---

## Test Credentials

| Field | Value |
|-------|-------|
| Username | `mcp-tester-1769879674` |
| Password | `McpTest2026!` |
| Realm | `mcp` |

---

## PKCE Parameters (Pre-generated)

```bash
CODE_VERIFIER=tWYrxkwdz2YU75ejekBiXzdDZ-UdN1Qf17R0PdR1L-U
CODE_CHALLENGE=SsorjfBzLVOMgD7XSIKAURxEwlwEmJ80mD2uYNM71Tk
```

---

## Step 1: Open Authorization URL

Open this URL in your browser:

```
https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-1769879699&code_challenge=SsorjfBzLVOMgD7XSIKAURxEwlwEmJ80mD2uYNM71Tk&code_challenge_method=S256
```

**Expected Result:** Keycloak login page appears

**If you see an error redirect instead**, note the error message and stop here.

---

## Step 2: Login

Enter the test credentials:
- **Username:** `mcp-tester-1769879674`
- **Password:** `McpTest2026!`

Click "Sign In"

---

## Step 3: Capture Authorization Code

After successful login, your browser will redirect to:
```
http://localhost:8888/callback?code=AUTHORIZATION_CODE_HERE&state=test-1769879350&...
```

**The browser will show "Connection Refused"** - this is expected and normal.

**Action:** Copy the ENTIRE URL from your browser's address bar.

Example of what to copy:
```
http://localhost:8888/callback?code=abc123def456...&state=test-1769879350&session_state=...&iss=...
```

---

## Step 4: Extract the Code

From the URL you copied, extract just the `code` parameter value.

Example:
- Full URL: `http://localhost:8888/callback?code=abc123def456&state=test-1769879350`
- Code value: `abc123def456`

---

## Step 5: Exchange Code for Token

Run this command in terminal, replacing `YOUR_CODE_HERE` with the code from Step 4:

```bash
curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=YOUR_CODE_HERE" \
    -d "redirect_uri=http://localhost:8888/callback" \
    -d "code_verifier=tWYrxkwdz2YU75ejekBiXzdDZ-UdN1Qf17R0PdR1L-U" | python3 -m json.tool
```

**Expected Result:** JSON response containing `access_token`, `refresh_token`, `id_token`

Example success response:
```json
{
    "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 300,
    "refresh_expires_in": 1800,
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
    "scope": "openid email profile"
}
```

**If you get an error:** Note the error message. Common issues:
- `invalid_grant` - Code already used or expired (codes are single-use, expire in ~1 minute)
- `invalid_client` - Client secret issue

---

## Step 6: Test MCP Endpoint

Copy the `access_token` value from Step 5 and run:

```bash
ACCESS_TOKEN="paste-your-access-token-here"

timeout 5 curl -v \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://alanhoangnguyen.com/mcp/sse
```

**Expected Result:**
- HTTP 200 OK
- SSE connection established (may see `data:` lines or connection stays open)

---

## Step 7: Verify JWT Validator Logs (Server-Side)

On the production server, check that the token was validated:

```bash
docker logs jwt_validator --tail 20
```

**Expected:** Log line showing `Token validated successfully for subject: ...`

---

## Success Criteria

| Step | Expected Outcome |
|------|------------------|
| Step 1 | Keycloak login page loads (no PKCE error) |
| Step 2 | Login succeeds, redirects to callback |
| Step 3 | URL contains `code=` parameter |
| Step 5 | Token exchange returns `access_token` |
| Step 6 | MCP endpoint returns HTTP 200 |
| Step 7 | JWT validator logs show successful validation |

---

## Troubleshooting

### "Missing parameter: code_challenge_method"
The authorization URL is missing PKCE parameters. Use the full URL provided in Step 1.

### "Invalid parameter: code_challenge"
PKCE code_challenge is malformed. Regenerate using:
```bash
CODE_VERIFIER=$(LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
echo "CODE_VERIFIER=$CODE_VERIFIER"
echo "CODE_CHALLENGE=$CODE_CHALLENGE"
```

### "invalid_grant" on token exchange
- Authorization codes are single-use and expire quickly (~1 minute)
- Go back to Step 1 and get a fresh code
- Make sure you're using the exact `code_verifier` that matches the `code_challenge`

### "invalid_user_credentials" on login
- Verify username is `oauth-test` (not email)
- Password is `TestPassword123!`
- If still failing, a new test user may need to be created

### MCP endpoint returns 401
- Check JWT validator logs for specific error
- Token may have expired (5 minute lifespan)
- Get a fresh token and retry

---

## Generating Fresh PKCE Parameters

If you need new parameters (e.g., testing multiple times):

```bash
CODE_VERIFIER=$(LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')

echo "New CODE_VERIFIER: $CODE_VERIFIER"
echo "New CODE_CHALLENGE: $CODE_CHALLENGE"

# Build new authorization URL
echo "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-$(date +%s)&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"
```

---

## Report Template

After testing, report results:

```
## OAuth PKCE Flow Test Results

**Tester:**
**Date/Time:**

### Results

| Step | Status | Notes |
|------|--------|-------|
| 1. Auth URL | PASS/FAIL | |
| 2. Login | PASS/FAIL | |
| 3. Get Code | PASS/FAIL | |
| 5. Token Exchange | PASS/FAIL | |
| 6. MCP Endpoint | PASS/FAIL | |
| 7. JWT Logs | PASS/FAIL | |

### Errors Encountered
(paste any error messages here)

### Access Token Received
(paste first 50 chars): eyJhbGciOiJSUzI1NiIsInR5cCI...

### Token Scopes
(from token response):
```

---

## Related Documentation

- `mcp-oauth-scope-change-bridge-2026-01-31.md` - OAuth scope configuration details
- `oauth-implementation-status.md` - Full implementation status
- `keycloak-scope-assignment-problem.md` - Known Keycloak issues

---

**Last Updated:** 2026-01-31
