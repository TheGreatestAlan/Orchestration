# OAuth PKCE Flow Test Results
**Date:** 2026-01-31
**Tester:** Local Agent (automated with MCP Chrome DevTools)
**Test Duration:** ~15 minutes

---

## Test Summary

| Step | Status | Notes |
|------|--------|-------|
| 1. Authorization URL | ✓ PASS | Login page loaded successfully with PKCE parameters |
| 2. Login | ✓ PASS | Auto-login (existing session) |
| 3. Get Authorization Code | ✓ PASS | Code obtained successfully |
| 4. Token Exchange | ✗ FAIL | "Code not valid" error |
| 5. MCP Endpoint Test | ⊘ SKIP | No token obtained |

---

## Detailed Results

### Step 1-3: Authorization Flow ✓ SUCCESS

**Authorization URL used:**
```
https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/auth?client_id=chatgpt-mcp-client&redirect_uri=https://alanhoangnguyen.com/oauth-callback&response_type=code&scope=openid%20email%20profile&state=test-1769880401306&code_challenge=g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA&code_challenge_method=S256
```

**Result:**
- Keycloak login page loaded (no PKCE errors)
- Auto-login succeeded (existing session for mcp-tester user)
- Redirect to callback URL successful

**Callback URL received:**
```
https://alanhoangnguyen.com/oauth-callback?state=test-1769880401306&session_state=a225265e-389d-4d0a-aa52-1b383b25c199&iss=https%3A%2F%2Fauth.alanhoangnguyen.com%2Frealms%2Fmcp&code=07205c87-fb20-4ff2-b262-18de29d9b841.a225265e-389d-4d0a-aa52-1b383b25c199.a8f58fee-9f9d-4422-b4c5-df3596e1233f
```

**Authorization codes obtained:**
1. First attempt: `07205c87-fb20-4ff2-b262-18de29d9b841.a225265e-389d-4d0a-aa52-1b383b25c199.a8f58fee-9f9d-4422-b4c5-df3596e1233f`
2. Second attempt (fresh): `8133c8d8-7877-4813-9998-75254f5b58c1.a225265e-389d-4d0a-aa52-1b383b25c199.a8f58fee-9f9d-4422-b4c5-df3596e1233f`

---

### Step 4: Token Exchange ✗ FAILURE

**Error Response:**
```json
{
    "error": "invalid_grant",
    "error_description": "Code not valid"
}
```

**Token Exchange Request:**
```bash
curl -X POST "https://auth.alanhoangnguyen.com/realms/mcp/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=authorization_code" \
    -d "client_id=chatgpt-mcp-client" \
    -d "client_secret=8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu" \
    -d "code=8133c8d8-7877-4813-9998-75254f5b58c1.a225265e-389d-4d0a-aa52-1b383b25c199.a8f58fee-9f9d-4422-b4c5-df3596e1233f" \
    -d "redirect_uri=https://alanhoangnguyen.com/oauth-callback" \
    -d "code_verifier=bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb"
```

**Attempts made:** 2 (both failed with same error)
**Time between code generation and exchange:** <5 seconds (well within 60 second limit)

---

## PKCE Parameter Verification

**Parameters used:**
```
code_verifier: bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb
code_challenge: g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA
```

**Verification test:**
```bash
$ echo -n "bRJlInKNcw8Erz3tWGnYb_JSplfLevrX8jsepsyXBSb" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
g7ySyfTmRn6gnh4Ps9BBeb0fQI0nFXW5CyjtAG7PWYA
```

**✓ PKCE parameters are cryptographically correct**

---

## Root Cause Analysis

The "Code not valid" error persists despite:
1. Fresh authorization codes (generated seconds before use)
2. Correct PKCE parameters (verified cryptographically)
3. Matching redirect_uri
4. Valid client credentials

**Possible causes:**

### 1. Keycloak Client Configuration Issue
The client `chatgpt-mcp-client` may have:
- Incorrect redirect URI whitelist
- PKCE settings that don't match the flow
- Some other validation that's failing

**Action needed:** Review client settings in Keycloak admin console

### 2. Redirect URI Mismatch
The redirect_uri must match EXACTLY between:
- Authorization request: `https://alanhoangnguyen.com/oauth-callback`
- Token exchange request: `https://alanhoangnguyen.com/oauth-callback`
- Keycloak client config: Valid Redirect URIs

**Action needed:** Verify exact match (case-sensitive, no trailing slash, etc.)

### 3. Session State Issue
The authorization code format includes session state:
```
{uuid}.{session_state}.{client_session}
```

If there's a session validation issue, codes might be invalidated immediately.

**Action needed:** Check Keycloak server logs for specific error details

### 4. Code Already Consumed
OAuth codes are single-use. If something else is consuming the code before our exchange attempt, we'd see this error.

**Action needed:** Check if any webhooks/interceptors are consuming codes

---

## Keycloak Server-Side Investigation Required

To diagnose further, need to check Keycloak logs on the production server:

```bash
# Check recent token endpoint errors
docker logs keycloak --tail 100 | grep -i "token"

# Check for code validation errors
docker logs keycloak --tail 100 | grep -i "code"

# Check full logs during test
docker logs keycloak -f
```

Look for specific error messages that indicate:
- Why the code is considered "not valid"
- If PKCE validation is failing
- If redirect_uri doesn't match
- If client authentication is failing

---

## Comparison: Previous Test Issues

### Issue 1: PKCE Format (RESOLVED)
**Previous error:** `Invalid parameter: code_challenge`
**Cause:** Improper base64url encoding
**Resolution:** Production agent provided correctly formatted PKCE parameters

### Issue 2: Test User Credentials (RESOLVED)
**Previous error:** `Invalid username or password` for oauth-test user
**Resolution:** Production agent created new test user `mcp-tester-1769879674`

### Issue 3: Redirect URI (RESOLVED)
**Previous issue:** localhost:8888/callback caused connection refused
**Resolution:** Changed to production callback https://alanhoangnguyen.com/oauth-callback

### Current Issue: Code Validation (UNRESOLVED)
**Current error:** `Code not valid`
**Status:** Blocking - requires server-side investigation

---

## Next Steps

1. **Check Keycloak client configuration**
   - Verify Valid Redirect URIs includes `https://alanhoangnguyen.com/oauth-callback`
   - Verify PKCE is enabled and set to S256
   - Check any other validation settings

2. **Review Keycloak server logs**
   - Get specific error message for "Code not valid"
   - Check if code is being consumed/invalidated prematurely

3. **Test with different redirect URI**
   - Try with a redirect URI that has an actual endpoint
   - Or try with the original localhost callback

4. **Verify client secret**
   - Confirm `8ddjAIUo2sv2Eqrb2tyES7jz525LGhuu` is correct
   - Try regenerating client secret if needed

5. **Test without auto-login**
   - Clear browser session
   - Manual login to see if session state affects code validity

---

## Technical Details

### Browser Testing
- **Method:** Automated via MCP Chrome DevTools server
- **Browser:** Chromium (debug mode, port 9222)
- **Session:** Existing session present (auto-login occurred)

### PKCE Implementation
- **Code Verifier:** 43 characters, URL-safe base64
- **Code Challenge Method:** S256 (SHA-256)
- **Code Challenge:** Base64url-encoded SHA-256 hash

### Authorization Code Format
```
{code_id}.{session_state}.{client_session_id}
Example: 8133c8d8-7877-4813-9998-75254f5b58c1.a225265e-389d-4d0a-aa52-1b383b25c199.a8f58fee-9f9d-4422-b4c5-df3596e1233f
```

---

## Conclusion

**OAuth Authorization flow is working correctly:**
- ✓ PKCE parameters are valid
- ✓ Login/authentication succeeds
- ✓ Authorization codes are generated

**Token exchange is failing:**
- ✗ All codes rejected as "not valid"
- ✗ Error occurs server-side (Keycloak validation)
- ✗ Root cause unclear without server logs

**Recommendation:** Investigate Keycloak server-side configuration and logs to identify why codes are being rejected during token exchange despite meeting all OAuth 2.1 + PKCE requirements.

---

**Files Generated:**
- `/tmp/exchange-code.sh` - Script for quick code exchange testing
- This report: `oauth-test-results-2026-01-31.md`

**References:**
- Test instructions: `mcp-oauth-local-test-2026-01-31.md`
- Initial findings: `oauth-authorization-code-flow-testing-findings.md`
