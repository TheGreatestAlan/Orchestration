# OAuth Authorization Code Flow Testing Findings
## Date: 2026-01-31

## Objective
Test the OAuth 2.1 Authorization Code flow with the MCP realm using automated browser testing via Chrome DevTools MCP server.

## Environment
- **Keycloak Server**: auth.alanhoangnguyen.com
- **Realm**: mcp
- **Client ID**: chatgpt-mcp-client
- **Redirect URI**: http://localhost:8888/callback
- **Test User**: oauth-test / TestPassword123!
- **Required Scopes**: openid, email, profile

## Key Findings

### 1. PKCE Requirement Detected

The OAuth client `chatgpt-mcp-client` is configured to **require PKCE** (Proof Key for Code Exchange), which is part of OAuth 2.1 best practices.

**Initial Authorization Request (without PKCE):**
```
GET https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-123
```

**Server Response:**
```
HTTP/2 302
location: http://localhost:8888/callback?error=invalid_request&error_description=Missing+parameter%3A+code_challenge_method&state=test-123&iss=https%3A%2F%2Fauth.alanhoangnguyen.com%2Frealms%2Fmcp
```

**Error**: `Missing parameter: code_challenge_method`

This confirms that PKCE is mandatory for this OAuth client.

### 2. Code Challenge Generation Issue

Generated PKCE parameters:
```bash
CODE_VERIFIER=X49Z823xdbchuVMhIRMGKahGeqqNcrxbE5g84boBU
CODE_CHALLENGE=BM6wqK1GK7DVQiTpAq8gXJBAoLBqxmiBBAixmkR7E
```

**Authorization Request with PKCE:**
```
GET https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=http://localhost:8888/callback&response_type=code&scope=openid%20email%20profile&state=test-123&code_challenge=BM6wqK1GK7DVQiTpAq8gXJBAoLBqxmiBBAixmkR7E&code_challenge_method=S256
```

**Server Response:**
```
HTTP/2 302
location: http://localhost:8888/callback?error=invalid_request&error_description=Invalid+parameter%3A+code_challenge&state=test-123&iss=https%3A%2F%2Fauth.alanhoangnguyen.com%2Frealms%2Fmcp
```

**Error**: `Invalid parameter: code_challenge`

### 3. Network Request Analysis

Browser network logs show repeated connection failures to localhost:8888/callback with the error parameters:

```
reqid=41 GET http://localhost:8888/callback?error=invalid_request&error_description=Invalid+parameter%3A+code_challenge&state=test-123&iss=https%3A%2F%2Fauth.alanhoangnguyen.com%2Frealms%2Fmcp [failed - net::ERR_CONNECTION_REFUSED]

reqid=45 GET http://localhost:8888/callback?error=invalid_request&error_description=Invalid+parameter%3A+code_challenge&state=test-123&iss=https%3A%2F%2Fauth.alanhoangnguyen.com%2Frealms%2Fmcp [failed - net::ERR_CONNECTION_REFUSED]
```

The connection refused is expected since there's no server on localhost:8888, but the error parameters indicate the OAuth flow is failing before authentication.

## Root Cause Analysis

### Possible Issues:

1. **Code Challenge Format**: The generated code_challenge may not be in the correct format. It should be base64url-encoded (URL-safe base64 without padding).

2. **Client Configuration**: The Keycloak client settings for `chatgpt-mcp-client` may have specific PKCE requirements that aren't being met.

3. **Code Challenge Length**: The code_challenge appears short (41 characters). Standard base64url encoding of SHA256 hash should be 43 characters.

### Code Challenge Generation Method Used:

```bash
CODE_VERIFIER=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr -d "=+/" | tr -d '\n')
```

**Issue**: The base64 encoding may need URL-safe encoding with proper padding handling.

## Recommended Actions

### 1. Fix Code Challenge Generation

Use proper base64url encoding:
```bash
CODE_VERIFIER=$(LC_ALL=C tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 43)
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
```

### 2. Verify Keycloak Client Configuration

Check the following settings in Keycloak admin console for `chatgpt-mcp-client`:
- **PKCE Code Challenge Method**: Should be S256
- **Proof Key for Code Exchange Code Challenge Method**: Verify it's set correctly
- **Valid Redirect URIs**: Confirm http://localhost:8888/callback is listed

### 3. Alternative Testing Approach

Since browser automation encountered issues, consider testing with curl directly:

```bash
# Step 1: Get authorization code (will fail without proper PKCE)
curl -v "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?..." \
  --cookie-jar cookies.txt \
  --location

# Step 2: Submit login form
# Step 3: Extract authorization code from redirect
# Step 4: Exchange code for token
```

## Browser Testing Notes

### MCP Chrome DevTools Server
- Successfully configured and connected
- Chromium running on port 9222
- Tools available: navigate, screenshot, snapshot, fill_form, click, etc.

### Navigation Issues
- Direct navigation to OAuth authorization URL initially failed with ERR_CONNECTION_REFUSED
- Workaround: Navigate to /realms/mcp/account first, then use JavaScript to navigate to auth endpoint
- This suggests potential browser security restrictions or redirect loop issues

### Test User Credentials
- Username: oauth-test
- Password: TestPassword123!
- Realm: mcp (not master realm)

## References

- PKCE RFC: https://datatracker.ietf.org/doc/html/rfc7636
- OAuth 2.1 Draft: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-09
- Keycloak PKCE Documentation

## Next Steps

1. Fix code_challenge generation to use proper base64url encoding
2. Verify Keycloak client PKCE configuration
3. Test with corrected PKCE parameters
4. If successful, capture authorization code and exchange for access token
5. Test MCP endpoint with obtained access token

## Status

**BLOCKED**: OAuth flow fails at authorization step due to invalid code_challenge parameter. PKCE implementation needs correction before proceeding with end-to-end testing.
