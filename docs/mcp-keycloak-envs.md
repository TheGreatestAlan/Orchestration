# MCP + Keycloak OAuth Env Configuration

Date: 2026-01-31
Owner: OrganizerServer
Scope: Env vars for MCP to accept OAuth tokens (Keycloak) AND API key

## Required MCP env vars (prod compose/env file)

```
MCP_OAUTH_ENABLED=true
MCP_OAUTH_ISSUER=https://alanhoangnguyen.com/oauth/realms/mcp
MCP_OAUTH_AUDIENCE=https://alanhoangnguyen.com/mcp
MCP_OAUTH_SCOPES=inventory:read,inventory:write
```

Optional (if JWKS URL is not at default issuer path):
```
MCP_OAUTH_JWKS_URL=https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs
```

Keep API key support (optional but recommended for non‑ChatGPT clients):
```
MCP_API_KEY=...  # still accepted alongside OAuth tokens
```

## Notes
- The MCP server validates JWT `iss` and `aud` against the values above.
- `MCP_OAUTH_ISSUER` must match Keycloak realm issuer exactly.
- After setting env vars, restart the `organizerserver` service using the 0.1.3 image.
