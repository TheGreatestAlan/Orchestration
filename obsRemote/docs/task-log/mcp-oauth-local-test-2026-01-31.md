# MCP OAuth Test - Run From Local Machine

**Date:** 2026-01-31
**Purpose:** Test OAuth 2.1 Authorization Code flow with PKCE from a local machine

---

## Why Local?

The authorization code expires in ~60 seconds. Running the token exchange locally eliminates network/chat latency.

---

## Test Script

Save this as `test-mcp-oauth.sh` and run it:

```bash
#!/bin/bash
# MCP OAuth Test Script
# Run this on your local machine

echo "=== MCP OAuth PKCE Test ==="
echo ""
echo "Step 1: Open this URL in your browser:"
echo ""
echo "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=https://alanhoangnguyen.com/oauth-callback&response_type=code&scope=openid%20email%20profile&state=test-$(date +%s)&code_challenge=g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA&code_challenge_method=S256"
echo ""
echo "Step 2: Login with:"
echo "  Username: mcp-tester-1769879674"
echo "  Password: McpTest2026!"
echo ""
echo "Step 3: After redirect, copy JUST the code= value from the URL"
echo "  Example URL: https://alanhoangnguyen.com/oauth-callback?state=...&code=abc-123-def"
echo "  You would paste: abc-123-def"
echo ""

read -p "Paste the code value here: " CODE

if [ -z "$CODE" ]; then
    echo "No code provided. Exiting."
    exit 1
fi

echo ""
echo "Exchanging code for token..."

RESPONSE=$(curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=$CODE" \
    -d "redirect_uri=https://alanhoangnguyen.com/oauth-callback" \
    -d "code_verifier=bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb")

echo ""
echo "=== Token Response ==="
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# Extract access token
ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    echo ""
    echo "ERROR: Failed to get access token"
    echo "Check the response above for error details"
    exit 1
fi

echo ""
echo "=== Access Token Obtained ==="
echo "Token (first 50 chars): ${ACCESS_TOKEN:0:50}..."
echo ""
echo "=== Testing MCP SSE Endpoint ==="

timeout 5 curl -i \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    https://alanhoangnguyen.com/mcp/sse 2>&1

echo ""
echo ""
echo "=== Test Complete ==="
echo "If you see HTTP 200 above, OAuth is working!"
```

---

## Manual Steps (Alternative)

If you prefer to run commands manually:

### 1. Open Authorization URL

```
https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=https://alanhoangnguyen.com/oauth-callback&response_type=code&scope=openid%20email%20profile&state=test-manual&code_challenge=g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA&code_challenge_method=S256
```

### 2. Login

- Username: `mcp-tester-1769879674`
- Password: `McpTest2026!`

### 3. Copy the Code

From the callback URL, copy the `code=` value.

### 4. Exchange Code for Token (run immediately)

```bash
CODE="paste-code-here"

curl -s -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=$CODE" \
    -d "redirect_uri=https://alanhoangnguyen.com/oauth-callback" \
    -d "code_verifier=bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb" | python3 -m json.tool
```

### 5. Test MCP Endpoint

```bash
ACCESS_TOKEN="paste-access-token-here"

curl -i -H "Authorization: Bearer $ACCESS_TOKEN" https://alanhoangnguyen.com/mcp/sse
```

---

## Expected Results

### Successful Token Response
```json
{
    "access_token": "eyJhbGciOiJSUzI1NiIs...",
    "expires_in": 300,
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "token_type": "Bearer",
    "scope": "openid email profile"
}
```

### Successful MCP Endpoint Response
```
HTTP/2 200
content-type: text/event-stream
...
```

---

## Troubleshooting

### "Code not valid" Error
- Code expired (>60 seconds old)
- Code already used (single-use only)
- **Fix:** Get a fresh code and try again faster

### "invalid_grant" Error
- Code/verifier mismatch
- **Fix:** Make sure you're using the code_verifier that matches the code_challenge in the auth URL

### 401 on MCP Endpoint
- Token expired or invalid
- **Fix:** Check token response for errors, get fresh token

---

## PKCE Parameters Used

```
code_verifier: bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb
code_challenge: g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA
```

These are cryptographically linked - the verifier must match the challenge.

---

## Report Results

After testing, report:

1. Did token exchange succeed? (yes/no)
2. What scopes are in the token response?
3. Did MCP endpoint return 200? (yes/no)
4. Any errors encountered?

---

**Last Updated:** 2026-01-31
