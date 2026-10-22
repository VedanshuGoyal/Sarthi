package olamaps

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// tokenServer is an httptest stand-in for Ola's token endpoint. It hands out
// token-1, token-2, … and records the last form it received. Its reply can be
// swapped mid-test with respond.
type tokenServer struct {
	calls atomic.Int32

	mu       sync.Mutex
	status   int
	body     func(n int32) string
	lastForm url.Values
	lastType string
}

func (ts *tokenServer) respond(status int, body func(n int32) string) {
	ts.mu.Lock()
	defer ts.mu.Unlock()
	ts.status, ts.body = status, body
}

func newTokenServer(t *testing.T, ts *tokenServer) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := ts.calls.Add(1)
		raw, _ := io.ReadAll(r.Body)
		form, _ := url.ParseQuery(string(raw))

		ts.mu.Lock()
		ts.lastForm = form
		ts.lastType = r.Header.Get("Content-Type")
		status, body := ts.status, ts.body
		ts.mu.Unlock()

		if status == 0 {
			status = http.StatusOK
		}
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body(n))
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func okBody(expiresIn int) func(int32) string {
	return func(n int32) string {
		return fmt.Sprintf(`{"access_token":"token-%d","expires_in":%d,"token_type":"Bearer"}`, n, expiresIn)
	}
}

func TestToken_ClientCredentialsGrant(t *testing.T) {
	ts := &tokenServer{body: okBody(3600)}
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)), WithClock(func() time.Time { return now }))

	tok, err := c.Token(context.Background())
	if err != nil {
		t.Fatalf("Token: %v", err)
	}
	if tok.AccessToken != "token-1" {
		t.Fatalf("AccessToken = %q, want token-1", tok.AccessToken)
	}
	if want := now.Add(time.Hour); !tok.ExpiresAt.Equal(want) {
		t.Fatalf("ExpiresAt = %v, want %v", tok.ExpiresAt, want)
	}
	if ts.lastType != "application/x-www-form-urlencoded" {
		t.Fatalf("Content-Type = %q", ts.lastType)
	}
	f := ts.lastForm
	if f.Get("grant_type") != "client_credentials" || f.Get("client_id") != "id" ||
		f.Get("client_secret") != "secret" || f.Get("scope") != "openid" {
		t.Fatalf("form = %v", f)
	}
}

func TestToken_CachedUntilNearExpiry(t *testing.T) {
	ts := &tokenServer{body: okBody(3600)}
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)), WithClock(func() time.Time { return now }))
	ctx := context.Background()

	first, _ := c.Token(ctx)
	now = now.Add(54 * time.Minute) // 6 min left: still above the 5 min floor
	second, _ := c.Token(ctx)
	if second.AccessToken != first.AccessToken || ts.calls.Load() != 1 {
		t.Fatalf("expected the cached token, got %q after %d calls", second.AccessToken, ts.calls.Load())
	}

	now = now.Add(2 * time.Minute) // 4 min left: refresh
	third, err := c.Token(ctx)
	if err != nil {
		t.Fatalf("Token: %v", err)
	}
	if third.AccessToken != "token-2" || ts.calls.Load() != 2 {
		t.Fatalf("expected a refreshed token, got %q after %d calls", third.AccessToken, ts.calls.Load())
	}
}

func TestToken_ShortLivedTokenStillReused(t *testing.T) {
	// A 4-minute token is below the 5-minute floor; it must still be reused
	// for the first half of its life rather than refetched on every call.
	ts := &tokenServer{body: okBody(240)}
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)), WithClock(func() time.Time { return now }))
	ctx := context.Background()

	_, _ = c.Token(ctx)
	now = now.Add(time.Minute)
	_, _ = c.Token(ctx)
	if ts.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1", ts.calls.Load())
	}
	now = now.Add(90 * time.Second) // past the halfway mark
	_, _ = c.Token(ctx)
	if ts.calls.Load() != 2 {
		t.Fatalf("calls = %d, want 2", ts.calls.Load())
	}
}

func TestToken_ConcurrentCallersShareOneRequest(t *testing.T) {
	ts := &tokenServer{body: okBody(3600)}
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)))

	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			if _, err := c.Token(context.Background()); err != nil {
				t.Errorf("Token: %v", err)
			}
		})
	}
	wg.Wait()
	if ts.calls.Load() != 1 {
		t.Fatalf("calls = %d, want 1", ts.calls.Load())
	}
}

func TestToken_ProviderErrorNotCached(t *testing.T) {
	ts := &tokenServer{
		status: http.StatusUnauthorized,
		body: func(int32) string {
			return `{"error":"unauthorized_client","error_description":"Invalid client secret"}`
		},
	}
	c := New("id", "wrong", WithTokenURL(newTokenServer(t, ts)))

	if _, err := c.Token(context.Background()); err == nil {
		t.Fatal("expected an error on 401")
	}
	ts.respond(http.StatusOK, okBody(3600))
	tok, err := c.Token(context.Background())
	if err != nil || tok.AccessToken == "" {
		t.Fatalf("after recovery: tok=%q err=%v", tok.AccessToken, err)
	}
}

func TestToken_MissingAccessToken(t *testing.T) {
	ts := &tokenServer{body: func(int32) string { return `{"expires_in":3600}` }}
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)))
	if _, err := c.Token(context.Background()); err == nil {
		t.Fatal("expected an error when access_token is absent")
	}
}

func TestToken_DefaultLifetimeWhenExpiresInMissing(t *testing.T) {
	ts := &tokenServer{body: func(int32) string { return `{"access_token":"t"}` }}
	now := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	c := New("id", "secret", WithTokenURL(newTokenServer(t, ts)), WithClock(func() time.Time { return now }))
	tok, err := c.Token(context.Background())
	if err != nil {
		t.Fatalf("Token: %v", err)
	}
	if want := now.Add(defaultLifetime); !tok.ExpiresAt.Equal(want) {
		t.Fatalf("ExpiresAt = %v, want %v", tok.ExpiresAt, want)
	}
}
