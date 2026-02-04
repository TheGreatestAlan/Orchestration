# Keycloak OAuth Setup for ChatGPT MCP

Date: 2026-01-31
Owner: OrganizerServer
Scope: Use Keycloak as the OAuth 2.1 authorization server for ChatGPT MCP access

## Goal
Run Keycloak as a separate container on the prod host and use it as the OAuth server that ChatGPT will connect to. MCP resource metadata should point to Keycloak as the authorization server.

## High‑level Flow
- ChatGPT discovers MCP Protected Resource Metadata on the MCP public URL.
- ChatGPT performs OAuth 2.1 (Authorization Code + PKCE S256) against Keycloak.
- MCP server validates the access token (JWT) using Keycloak’s issuer + JWKS.

## Compose Additions (run_obsidian_remote.yml)
Add a **new service** (example name: `keycloak`) and a database (Postgres) or use Keycloak’s dev mode for faster setup.

### Option A: Quick start (dev mode)
Use only for initial testing; not recommended for production.

```
keycloak:
  image: quay.io/keycloak/keycloak:latest
  command: ["start-dev"]
  environment:
    KC_HOSTNAME: alanhoangnguyen.com
    KC_PROXY: edge
    KC_HTTP_ENABLED: "true"
    KC_HOSTNAME_STRICT: "false"
    KEYCLOAK_ADMIN: admin
    KEYCLOAK_ADMIN_PASSWORD: <SET_IN_ENV_FILE>
  ports:
    - "8087:8080"
```

### Option B: Production (Postgres)
Recommended for production.

```
keycloak:
  image: quay.io/keycloak/keycloak:latest
  command: ["start"]
  environment:
    KC_HOSTNAME: alanhoangnguyen.com
    KC_PROXY: edge
    KC_HTTP_ENABLED: "true"
    KC_HOSTNAME_STRICT: "true"
    KC_DB: postgres
    KC_DB_URL_HOST: keycloak-db
    KC_DB_URL_PORT: 5432
    KC_DB_URL_DATABASE: keycloak
    KC_DB_USERNAME: keycloak
    KC_DB_PASSWORD: <SET_IN_ENV_FILE>
    KEYCLOAK_ADMIN: admin
    KEYCLOAK_ADMIN_PASSWORD: <SET_IN_ENV_FILE>
  depends_on:
    - keycloak-db

keycloak-db:
  image: postgres:16
  environment:
    POSTGRES_DB: keycloak
    POSTGRES_USER: keycloak
    POSTGRES_PASSWORD: <SET_IN_ENV_FILE>
  volumes:
    - keycloak_db:/var/lib/postgresql/data

volumes:
  keycloak_db:
```

## Nginx Routing
Expose Keycloak on a public path, for example:
- `https://alanhoangnguyen.com/oauth/` → Keycloak

Proxy to `http://keycloak:8080/` and set standard headers. Ensure TLS is terminated at nginx and Keycloak sees `KC_PROXY=edge`.

## Keycloak Configuration Steps
1) **Create a Realm**: `mcp`
2) **Create a Client** for ChatGPT
   - Client type: OpenID Connect
   - Access type: **Confidential**
   - Standard flow: **ON**
   - PKCE: **S256 required**
   - Client Authentication: ON
   - Redirect URIs: **MUST match OpenAI/ChatGPT connector redirect URIs**
     - Ask the OpenAI docs for the exact URIs (do not guess). Add both production and review URIs.
   - Web Origins: set to the same origin(s) as redirect URIs
   - Enable **Dynamic Client Registration (DCR)**
     - In Keycloak: Realm Settings → Client Registration → set to “Enabled”
     - Configure registration policy if needed

3) **Create a User** (single shared login)
   - Username: `mcp-user` (example)
   - Password: set in Keycloak UI
   - Required Actions: none

4) **Configure Scopes**
   - Create two client scopes:
     - `inventory:read`
     - `inventory:write`
   - Map scopes to roles if you want future RBAC

## MCP Server Requirements
The MCP server must validate:
- JWT `iss` matches Keycloak issuer
- JWT signature via Keycloak JWKS
- `aud` (or `resource`) equals the MCP resource URL
- `scope` contains required scopes

If the current MCP implementation does **not** validate JWTs, add a shim that checks these values before proxying to the internal MCP server.

## MCP Protected Resource Metadata
Expose this at:
- `https://alanhoangnguyen.com/.well-known/oauth-protected-resource`

Example payload:
```
{
  "resource": "https://alanhoangnguyen.com/mcp",
  "authorization_servers": ["https://alanhoangnguyen.com/oauth/realms/mcp"],
  "scopes_supported": ["inventory:read", "inventory:write"],
  "resource_documentation": "https://alanhoangnguyen.com/docs/mcp"
}
```

## Keycloak Discovery Endpoints
Once realm is created:
- Issuer: `https://alanhoangnguyen.com/oauth/realms/mcp`
- OIDC discovery: `https://alanhoangnguyen.com/oauth/realms/mcp/.well-known/openid-configuration`
- JWKS: value from discovery `jwks_uri`

## Deployment Checklist
- [ ] Keycloak service is running and reachable via nginx
- [ ] Realm + client configured with correct redirect URIs
- [ ] DCR enabled
- [ ] MCP metadata points to Keycloak issuer
- [ ] MCP server validates JWT issuer/audience/scopes
- [ ] ChatGPT connector OAuth flow succeeds

## Notes
- This document configures OAuth only. The MCP server still needs a token verifier.
- If using a shim, the shim should validate JWTs then forward to internal MCP with its API key.
