// Package olamaps is an outbound adapter for Ola Maps' OAuth 2.0 token endpoint
// (client-credentials grant). The backend is the only holder of the client
// secret: it mints short-lived bearer tokens here and hands them to the apps
// (GET /maps/token), which send them on their own Places requests. A leaked
// app build or web bundle then exposes a token that expires on its own, never
// the secret.
//
// It implements service.MapsTokenSource.
package olamaps

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// defaultTokenURL is Ola's Keycloak token endpoint for the Maps realm.
const defaultTokenURL = "https://account.olamaps.io/realms/olamaps/protocol/openid-connect/token"

// defaultLifetime is assumed when Ola omits expires_in.
const defaultLifetime = time.Hour

// defaultMinRemaining is how much life a cached token must have left to be
// handed out again, so a token an app receives stays usable for a while after
// it arrives rather than expiring mid-search.
const defaultMinRemaining = 5 * time.Minute

// Client mints and caches Ola Maps bearer tokens. Safe for concurrent use.
type Client struct {
	clientID     string
	clientSecret string
	tokenURL     string
	http         *http.Client
	now          func() time.Time
	minRemaining time.Duration

	// mu guards the cached token and is held across a refresh, so concurrent
	// callers share one token request instead of stampeding Ola.
	mu        sync.Mutex
	token     domain.MapsToken
	refreshAt time.Time
}

// Option customises a Client (used mainly by tests to point at an httptest
// server or control the clock).
type Option func(*Client)

// WithTokenURL overrides the token endpoint (default [defaultTokenURL]).
func WithTokenURL(u string) Option {
	return func(c *Client) { c.tokenURL = u }
}

// WithHTTPClient overrides the underlying http.Client.
func WithHTTPClient(h *http.Client) Option {
	return func(c *Client) { c.http = h }
}

// WithClock overrides the time source.
func WithClock(now func() time.Time) Option {
	return func(c *Client) { c.now = now }
}

// New builds a Client for the given OAuth client credentials.
func New(clientID, clientSecret string, opts ...Option) *Client {
	c := &Client{
		clientID:     clientID,
		clientSecret: clientSecret,
		tokenURL:     defaultTokenURL,
		http:         &http.Client{Timeout: 10 * time.Second},
		now:          time.Now,
		minRemaining: defaultMinRemaining,
	}
	for _, opt := range opts {
		opt(c)
	}
	if c.tokenURL == "" {
		c.tokenURL = defaultTokenURL
	}
	return c
}

// Token returns the cached token while it still has enough life left, and
// otherwise fetches a fresh one. A failed fetch is not cached: the next call
// tries again.
func (c *Client) Token(ctx context.Context) (domain.MapsToken, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.token.AccessToken != "" && c.now().Before(c.refreshAt) {
		return c.token, nil
	}

	token, lifetime, err := c.fetch(ctx)
	if err != nil {
		return domain.MapsToken{}, err
	}
	// Refresh once less than minRemaining is left — but never later than
	// halfway, so a short-lived token is still reused at least briefly.
	leeway := min(c.minRemaining, lifetime/2)
	c.token = token
	c.refreshAt = token.ExpiresAt.Add(-leeway)
	return token, nil
}

// tokenResponse is the slice of Ola's OAuth reply we use.
type tokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int    `json:"expires_in"`
}

// fetch runs one client-credentials exchange and returns the token with its
// lifetime.
func (c *Client) fetch(ctx context.Context) (domain.MapsToken, time.Duration, error) {
	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {c.clientID},
		"client_secret": {c.clientSecret},
		"scope":         {"openid"},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: build token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	issuedAt := c.now()
	resp, err := c.http.Do(req)
	if err != nil {
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: token request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if err != nil {
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: read token response: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		// Keycloak's error body ({"error":…,"error_description":…}) names the
		// problem (e.g. a bad secret) without echoing the secret itself.
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: token request failed: status %d: %s",
			resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var payload tokenResponse
	if err := json.Unmarshal(body, &payload); err != nil {
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: decode token response: %w", err)
	}
	if payload.AccessToken == "" {
		return domain.MapsToken{}, 0, fmt.Errorf("olamaps: token response carried no access_token")
	}

	lifetime := defaultLifetime
	if payload.ExpiresIn > 0 {
		lifetime = time.Duration(payload.ExpiresIn) * time.Second
	}
	return domain.MapsToken{
		AccessToken: payload.AccessToken,
		// Measured from before the request went out, so network latency can
		// only make our idea of the expiry early, never late.
		ExpiresAt: issuedAt.Add(lifetime),
	}, lifetime, nil
}
