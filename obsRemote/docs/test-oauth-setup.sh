#!/bin/bash
#
# OAuth 2.1 Setup Testing Script
# Run this after completing manual Keycloak configuration
#

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "OAuth 2.1 Setup Testing Script"
echo "======================================"
echo

# Test 1: OAuth Metadata
echo -e "${YELLOW}Test 1: OAuth Protected Resource Metadata${NC}"
if curl -sf https://alanhoangnguyen.com/.well-known/oauth-protected-resource > /dev/null; then
    echo -e "${GREEN}✓ OAuth metadata endpoint accessible${NC}"
    curl -s https://alanhoangnguyen.com/.well-known/oauth-protected-resource | python3 -m json.tool
else
    echo -e "${RED}✗ OAuth metadata endpoint failed${NC}"
    exit 1
fi
echo

# Test 2: Keycloak Health
echo -e "${YELLOW}Test 2: Keycloak Health Check${NC}"
if curl -sf https://alanhoangnguyen.com/oauth/health > /dev/null; then
    echo -e "${GREEN}✓ Keycloak is healthy${NC}"
else
    echo -e "${RED}✗ Keycloak health check failed${NC}"
    exit 1
fi
echo

# Test 3: OIDC Discovery
echo -e "${YELLOW}Test 3: OIDC Discovery Endpoint${NC}"
if curl -sf https://alanhoangnguyen.com/oauth/realms/mcp/.well-known/openid-configuration > /dev/null; then
    echo -e "${GREEN}✓ OIDC discovery endpoint accessible${NC}"
    curl -s https://alanhoangnguyen.com/oauth/realms/mcp/.well-known/openid-configuration | python3 -m json.tool | head -30
else
    echo -e "${RED}✗ OIDC discovery failed - Realm 'mcp' may not exist${NC}"
    echo -e "${YELLOW}Please create the 'mcp' realm in Keycloak${NC}"
    exit 1
fi
echo

# Test 4: JWKS Endpoint
echo -e "${YELLOW}Test 4: JWKS (Public Keys) Endpoint${NC}"
if curl -sf https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs > /dev/null; then
    echo -e "${GREEN}✓ JWKS endpoint accessible${NC}"
    KEY_COUNT=$(curl -s https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs | python3 -c "import sys, json; print(len(json.load(sys.stdin)['keys']))")
    echo "  Found $KEY_COUNT signing key(s)"
else
    echo -e "${RED}✗ JWKS endpoint failed${NC}"
    exit 1
fi
echo

# Test 5: MCP Endpoints Without Token
echo -e "${YELLOW}Test 5: MCP Endpoints (should require token)${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://alanhoangnguyen.com/mcp/sse)
if [ "$HTTP_CODE" = "401" ]; then
    echo -e "${GREEN}✓ MCP SSE endpoint correctly requires authorization (401)${NC}"
else
    echo -e "${RED}✗ MCP SSE endpoint returned unexpected status: $HTTP_CODE${NC}"
    exit 1
fi
echo

# Test 6: Token Request (if credentials provided)
echo -e "${YELLOW}Test 6: Token Request${NC}"
echo "To test token request, provide the following:"
read -p "Client Secret (from Keycloak): " CLIENT_SECRET
read -p "Test username (e.g., mcp-user): " USERNAME
read -s -p "Test user password: " PASSWORD
echo
echo

if [ -n "$CLIENT_SECRET" ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    echo "Requesting token..."
    TOKEN_RESPONSE=$(curl -s -X POST https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/token \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password" \
        -d "client_id=chatgpt-mcp-client" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "username=$USERNAME" \
        -d "password=$PASSWORD" \
        -d "scope=inventory:read inventory:write")

    if echo "$TOKEN_RESPONSE" | grep -q "access_token"; then
        echo -e "${GREEN}✓ Successfully obtained access token${NC}"
        ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
        EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['expires_in'])")
        echo "  Token expires in: $EXPIRES_IN seconds"
        echo

        # Test 7: MCP with valid token
        echo -e "${YELLOW}Test 7: MCP Endpoint with Valid Token${NC}"
        echo "Testing SSE endpoint with token..."
        HTTP_CODE=$(timeout 2 curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            https://alanhoangnguyen.com/mcp/sse || echo "200")

        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}✓ MCP SSE endpoint accessible with valid token${NC}"
        else
            echo -e "${RED}✗ MCP SSE endpoint failed with status: $HTTP_CODE${NC}"
            echo "Response:"
            curl -s -H "Authorization: Bearer $ACCESS_TOKEN" https://alanhoangnguyen.com/mcp/sse | head -20
        fi
    else
        echo -e "${RED}✗ Token request failed${NC}"
        echo "Response:"
        echo "$TOKEN_RESPONSE" | python3 -m json.tool || echo "$TOKEN_RESPONSE"
        exit 1
    fi
else
    echo -e "${YELLOW}⊘ Skipping token tests (no credentials provided)${NC}"
fi
echo

# Test 8: JWT Validator Health
echo -e "${YELLOW}Test 8: JWT Validator Service${NC}"
if docker ps --format "{{.Names}}" | grep -q "jwt_validator"; then
    STATUS=$(docker ps --format "{{.Status}}" --filter "name=jwt_validator")
    echo -e "${GREEN}✓ JWT Validator is running: $STATUS${NC}"
else
    echo -e "${RED}✗ JWT Validator is not running${NC}"
    exit 1
fi
echo

# Test 9: Service Health Summary
echo -e "${YELLOW}Test 9: Service Health Summary${NC}"
echo "Checking all OAuth services..."
docker ps --format "table {{.Names}}\t{{.Status}}" --filter "name=keycloak" --filter "name=jwt"
echo

# Summary
echo "======================================"
echo -e "${GREEN}All Tests Completed!${NC}"
echo "======================================"
echo
echo "Next steps:"
echo "1. Configure ChatGPT/Claude MCP connector with:"
echo "   - Authorization URL: https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/auth"
echo "   - Token URL: https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/token"
echo "   - Client ID: chatgpt-mcp-client"
echo "   - Client Secret: (from Keycloak)"
echo "   - Scopes: openid inventory:read inventory:write"
echo "2. Monitor logs: docker logs -f jwt_validator"
echo
