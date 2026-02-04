# MCP Production: Compose + Nginx Changes

Date: 2026-01-31
Owner: OrganizerServer
Scope: Production compose + nginx routing for MCP (SSE)

## Compose changes (run_obsidian_remote.yml)

Target service: `organizerserver`

1) Image
- Set image to registry tag that matches the new build pipeline:
  - `registry.alanhoangnguyen.com/admin/organizerserver:${ORGANIZER_VERSION:-latest}`

2) Environment
Add MCP env vars (values shown are required defaults):
- `MCP_TRANSPORT=sse`
- `MCP_PORT=3000`
- `MCP_API_KEY=...` (required unless OAuth is enabled)
- `INVENTORY_API_BASE_URL=http://localhost:8080`

Optional (recommended) DNS rebinding protection:
- `MCP_DNS_REBINDING_PROTECTION=true`
- `MCP_ALLOWED_HOSTS=alanhoangnguyen.com,www.alanhoangnguyen.com`
- `MCP_ALLOWED_ORIGINS=https://alanhoangnguyen.com,https://www.alanhoangnguyen.com`

Optional OAuth (API key OR OAuth bearer token accepted):
- `MCP_OAUTH_ENABLED=true`
- `MCP_OAUTH_ISSUER=https://alanhoangnguyen.com/oauth/realms/mcp`
- `MCP_OAUTH_AUDIENCE=https://alanhoangnguyen.com/mcp`
- `MCP_OAUTH_JWKS_URL=` (optional; defaults to Keycloak JWKS under issuer)
- `MCP_OAUTH_SCOPES=inventory:read,inventory:write`

3) Restart policy
- `restart: unless-stopped`

4) (Optional) Healthcheck
- Add an internal healthcheck against the admin port:
  - `curl -fsS http://localhost:8081/healthcheck`

Notes:
- Do not publish ports for `organizerserver`. MCP stays behind nginx.
- The MCP server runs in the same container and uses `localhost:8080` to reach Java.

## Nginx changes (handled on prod host)

Goal: expose MCP SSE endpoint over HTTPS and require API key auth.

Key requirements:
- Forward to the internal MCP server at `http://organizerserver:3000`.
- SSE endpoint is `/sse` and message endpoint is `/messages/`.
- Enforce `Authorization: Bearer <MCP_API_KEY>`.
- Keep SSE connections open (no buffering).

Suggested nginx location blocks (example only):

```
location /mcp/sse {
  proxy_pass http://organizerserver:3000/sse;
  proxy_http_version 1.1;
  proxy_set_header Connection "";
  proxy_buffering off;
  proxy_cache off;
  proxy_read_timeout 3600s;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;

  # Enforce API key auth (nginx should reject if missing or incorrect)
  if ($http_authorization != "Bearer ${MCP_API_KEY}") { return 401; }
}

location /mcp/messages/ {
  proxy_pass http://organizerserver:3000/messages/;
  proxy_http_version 1.1;
  proxy_set_header Connection "";
  proxy_buffering off;
  proxy_cache off;
  proxy_read_timeout 3600s;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;

  if ($http_authorization != "Bearer ${MCP_API_KEY}") { return 401; }
}
```

Notes:
- Use your existing site/server block and TLS configuration.
- The nginx `if` example assumes the API key is available in the nginx config
  (through envsubst or an include). If you enforce auth differently, keep the
  requirement: reject any request without a matching Bearer token.
- Nginx changes are handled on prod separately; this repo does not modify nginx.

## Verification checklist

- Compose service uses the new image tag and env vars.
- Container starts both Java + MCP (one container, two processes).
- `curl -fsS http://localhost:8081/healthcheck` succeeds inside container.
- External MCP requests return 401 without auth and 200/stream with valid auth.
