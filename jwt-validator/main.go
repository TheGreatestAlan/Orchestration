package main

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Configuration from environment variables
type Config struct {
	Port                   string
	KeycloakIssuer         string
	KeycloakJWKSURI        string
	MCPAPIKey              string
	MCPBackendURL          string
	MCPBackendObsidianURL  string
	ExpectedAudience       string
	RequiredScopes         []string
	JWKSCacheTTL           time.Duration
	LogLevel               string
}

// JWKS structures
type JWKS struct {
	Keys []JWK `json:"keys"`
}

type JWK struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// JWT Validator service
type JWTValidator struct {
	config      Config
	keysCache   map[string]*rsa.PublicKey
	cacheExpiry time.Time
	cacheMutex  sync.RWMutex
	httpClient  *http.Client
}

// Custom claims structure
type MCPClaims struct {
	Scope string `json:"scope"`
	jwt.RegisteredClaims
}

func loadConfig() Config {
	port := getEnv("PORT", "9000")
	jwksCacheTTL, _ := time.ParseDuration(getEnv("JWKS_CACHE_TTL", "3600") + "s")

	scopesStr := getEnv("REQUIRED_SCOPES", "")
	scopes := strings.Split(scopesStr, ",")
	for i, s := range scopes {
		scopes[i] = strings.TrimSpace(s)
	}

	return Config{
		Port:                   port,
		KeycloakIssuer:         getEnv("KEYCLOAK_ISSUER", "https://alanhoangnguyen.com/oauth/realms/mcp"),
		KeycloakJWKSURI:        getEnv("KEYCLOAK_JWKS_URI", "https://alanhoangnguyen.com/oauth/realms/mcp/protocol/openid-connect/certs"),
		MCPAPIKey:              os.Getenv("MCP_API_KEY"),
		MCPBackendURL:          getEnv("MCP_BACKEND_URL", "http://organizerserver:3000"),
		MCPBackendObsidianURL:  getEnv("MCP_BACKEND_OBSIDIAN_URL", "http://mcp-obsidian:3000"),
		ExpectedAudience:       getEnv("EXPECTED_AUDIENCE", "https://alanhoangnguyen.com/mcp"),
		RequiredScopes:         scopes,
		JWKSCacheTTL:           jwksCacheTTL,
		LogLevel:               getEnv("LOG_LEVEL", "INFO"),
	}
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func NewJWTValidator(config Config) *JWTValidator {
	return &JWTValidator{
		config:     config,
		keysCache:  make(map[string]*rsa.PublicKey),
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

// Fetch and cache JWKS
func (v *JWTValidator) fetchJWKS() error {
	v.cacheMutex.Lock()
	defer v.cacheMutex.Unlock()

	// Check if cache is still valid
	if time.Now().Before(v.cacheExpiry) {
		return nil
	}

	resp, err := v.httpClient.Get(v.config.KeycloakJWKSURI)
	if err != nil {
		return fmt.Errorf("failed to fetch JWKS: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("JWKS endpoint returned status %d", resp.StatusCode)
	}

	var jwks JWKS
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return fmt.Errorf("failed to decode JWKS: %w", err)
	}

	// Convert JWKs to RSA public keys
	newCache := make(map[string]*rsa.PublicKey)
	for _, key := range jwks.Keys {
		if key.Kty != "RSA" {
			continue
		}

		pubKey, err := jwkToRSAPublicKey(key)
		if err != nil {
			log.Printf("WARN: Failed to convert JWK %s: %v", key.Kid, err)
			continue
		}

		newCache[key.Kid] = pubKey
	}

	v.keysCache = newCache
	v.cacheExpiry = time.Now().Add(v.config.JWKSCacheTTL)

	log.Printf("INFO: JWKS cache refreshed with %d keys", len(v.keysCache))
	return nil
}

// Convert JWK to RSA public key
func jwkToRSAPublicKey(jwk JWK) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
	if err != nil {
		return nil, fmt.Errorf("failed to decode N: %w", err)
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
	if err != nil {
		return nil, fmt.Errorf("failed to decode E: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	var e int
	for _, b := range eBytes {
		e = e<<8 | int(b)
	}

	return &rsa.PublicKey{
		N: n,
		E: e,
	}, nil
}

// Get public key for token verification
func (v *JWTValidator) getKey(token *jwt.Token) (interface{}, error) {
	// Ensure token uses RS256
	if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
		return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
	}

	kid, ok := token.Header["kid"].(string)
	if !ok {
		return nil, fmt.Errorf("token missing kid header")
	}

	// Try to get key from cache
	v.cacheMutex.RLock()
	key, exists := v.keysCache[kid]
	v.cacheMutex.RUnlock()

	if exists {
		return key, nil
	}

	// Cache miss - refresh and try again
	if err := v.fetchJWKS(); err != nil {
		return nil, fmt.Errorf("failed to refresh JWKS: %w", err)
	}

	v.cacheMutex.RLock()
	key, exists = v.keysCache[kid]
	v.cacheMutex.RUnlock()

	if !exists {
		return nil, fmt.Errorf("key with kid %s not found", kid)
	}

	return key, nil
}

// Validate JWT token
func (v *JWTValidator) validateToken(tokenString string) (*MCPClaims, error) {
	var claims MCPClaims

	token, err := jwt.ParseWithClaims(tokenString, &claims, v.getKey)
	if err != nil {
		return nil, fmt.Errorf("token parsing failed: %w", err)
	}

	if !token.Valid {
		return nil, fmt.Errorf("token is invalid")
	}

	// Validate issuer
	if claims.Issuer != v.config.KeycloakIssuer {
		return nil, fmt.Errorf("invalid issuer: got %s, expected %s", claims.Issuer, v.config.KeycloakIssuer)
	}

	// Validate audience
	validAudience := false
	for _, aud := range claims.Audience {
		if aud == v.config.ExpectedAudience {
			validAudience = true
			break
		}
	}
	if !validAudience {
		return nil, fmt.Errorf("invalid audience: expected %s, got %v", v.config.ExpectedAudience, claims.Audience)
	}

	// Validate expiration
	if claims.ExpiresAt != nil && time.Now().After(claims.ExpiresAt.Time) {
		return nil, fmt.Errorf("token expired")
	}

	// Validate scopes
	tokenScopes := strings.Split(claims.Scope, " ")
	if !containsAllScopes(tokenScopes, v.config.RequiredScopes) {
		return nil, fmt.Errorf("insufficient scopes: got [%s], required %v", claims.Scope, v.config.RequiredScopes)
	}

	return &claims, nil
}

// Check if token has all required scopes
func containsAllScopes(tokenScopes, requiredScopes []string) bool {
	// If no scopes are required, allow all tokens
	if len(requiredScopes) == 0 || (len(requiredScopes) == 1 && requiredScopes[0] == "") {
		return true
	}

	scopeMap := make(map[string]bool)
	for _, s := range tokenScopes {
		scopeMap[s] = true
	}

	for _, required := range requiredScopes {
		if required == "" {
			continue
		}
		if !scopeMap[required] {
			return false
		}
	}

	return true
}

// HTTP middleware for JWT validation
func (v *JWTValidator) jwtMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Extract Authorization header
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, `{"error":"missing_authorization","error_description":"Authorization header is required"}`, http.StatusUnauthorized)
			return
		}

		// Extract Bearer token
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			http.Error(w, `{"error":"invalid_authorization","error_description":"Authorization header must be in format: Bearer <token>"}`, http.StatusUnauthorized)
			return
		}

		tokenString := parts[1]

		// Validate token
		claims, err := v.validateToken(tokenString)
		if err != nil {
			log.Printf("WARN: Token validation failed: %v", err)
			http.Error(w, fmt.Sprintf(`{"error":"invalid_token","error_description":"%s"}`, err.Error()), http.StatusUnauthorized)
			return
		}

		log.Printf("INFO: Token validated successfully for subject: %s", claims.Subject)

		// Add MCP API key for backend
		r.Header.Set("X-MCP-API-Key", v.config.MCPAPIKey)

		// Continue to proxy
		next.ServeHTTP(w, r)
	})
}

// getBackendURL determines the backend URL based on the request path
func (v *JWTValidator) getBackendURL(path string) string {
	// Route /mcp/obsidian to the obsidian backend
	if strings.HasPrefix(path, "/mcp/obsidian") {
		return v.config.MCPBackendObsidianURL + "/mcp"
	}
	// Default: route to inventory/organizerserver backend
	return v.config.MCPBackendURL + path
}

// Proxy handler
func (v *JWTValidator) proxyHandler(w http.ResponseWriter, r *http.Request) {
	// Build backend URL based on path routing
	backendURL := v.getBackendURL(r.URL.Path)
	if r.URL.RawQuery != "" {
		backendURL += "?" + r.URL.RawQuery
	}

	// Create proxy request
	proxyReq, err := http.NewRequestWithContext(context.Background(), r.Method, backendURL, r.Body)
	if err != nil {
		log.Printf("ERROR: Failed to create proxy request: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Copy headers (except Host which we'll set explicitly)
	for key, values := range r.Header {
		if key == "Host" {
			continue // Skip Host, we'll set it explicitly
		}
		for _, value := range values {
			proxyReq.Header.Add(key, value)
		}
	}

	// Set Host header to the original client request host
	// This is required for MCP server's DNS rebinding protection
	if originalHost := r.Header.Get("Host"); originalHost != "" {
		proxyReq.Host = originalHost
	}

	// Ensure Authorization header is forwarded (already copied in loop above)
	// MCP server will validate the OAuth token using its OAuth configuration

	// Execute request
	client := &http.Client{Timeout: 3600 * time.Second} // Long timeout for SSE
	resp, err := client.Do(proxyReq)
	if err != nil {
		log.Printf("ERROR: Proxy request failed: %v", err)
		http.Error(w, "Backend unavailable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	// Copy response headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}

	w.WriteHeader(resp.StatusCode)

	// Check if this is an SSE response that needs special streaming handling
	contentType := resp.Header.Get("Content-Type")
	isSSE := strings.Contains(contentType, "text/event-stream")

	if isSSE {
		// SSE requires immediate flushing of each event
		flusher, ok := w.(http.Flusher)
		if !ok {
			log.Printf("ERROR: ResponseWriter does not support Flusher interface")
			http.Error(w, "Streaming not supported", http.StatusInternalServerError)
			return
		}

		// Stream SSE events with immediate flushing
		buf := make([]byte, 4096)
		for {
			n, err := resp.Body.Read(buf)
			if n > 0 {
				if _, writeErr := w.Write(buf[:n]); writeErr != nil {
					log.Printf("WARN: Error writing SSE response: %v", writeErr)
					return
				}
				flusher.Flush()
			}
			if err != nil {
				if err != io.EOF {
					log.Printf("WARN: Error reading SSE response: %v", err)
				}
				return
			}
		}
	} else {
		// Non-SSE response: use standard copy
		if _, err := io.Copy(w, resp.Body); err != nil {
			log.Printf("WARN: Error streaming response: %v", err)
		}
	}
}

// Health check endpoint
func (v *JWTValidator) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
		"time":   time.Now().Format(time.RFC3339),
	})
}

func main() {
	config := loadConfig()

	// Validate required config
	if config.MCPAPIKey == "" {
		log.Fatal("FATAL: MCP_API_KEY environment variable is required")
	}

	validator := NewJWTValidator(config)

	// Initial JWKS fetch
	if err := validator.fetchJWKS(); err != nil {
		log.Printf("WARN: Initial JWKS fetch failed (will retry on first request): %v", err)
	}

	// Setup routes
	mux := http.NewServeMux()

	// Health check (no auth required)
	mux.HandleFunc("/health", validator.healthHandler)

	// Protected MCP endpoints
	// Streamable HTTP (current MCP transport - single endpoint)
	mux.Handle("/mcp", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))
	// Obsidian MCP server (path-based routing to different backend)
	mux.Handle("/mcp/obsidian", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))
	// Legacy SSE endpoints (kept for backward compatibility)
	mux.Handle("/sse", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))
	mux.Handle("/messages/", validator.jwtMiddleware(http.HandlerFunc(validator.proxyHandler)))

	// Start server
	addr := ":" + config.Port
	log.Printf("INFO: JWT Validator starting on %s", addr)
	log.Printf("INFO: Keycloak issuer: %s", config.KeycloakIssuer)
	log.Printf("INFO: MCP backend (default): %s", config.MCPBackendURL)
	log.Printf("INFO: MCP backend (obsidian): %s", config.MCPBackendObsidianURL)
	log.Printf("INFO: Required scopes: %v", config.RequiredScopes)

	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal("FATAL: Server failed to start: ", err)
	}
}
