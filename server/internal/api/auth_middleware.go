package api

import (
	"context"
	"net/http"
	"strings"
)

// ctxKey is a private context-key type so values set here can't collide with
// keys from other packages.
type ctxKey int

const (
	userIDKey ctxKey = iota
	tokenKey
)

// Authenticator validates a bearer token, returning the associated user id.
// Implemented by service.SessionService (cache-backed, no DB hit).
type Authenticator interface {
	Validate(token string) (userID string, ok bool)
}

// requireAuth wraps a handler so it only runs for requests carrying a valid
// `Authorization: Bearer <token>` header. It stashes the user id and token in
// the request context for the handler.
func requireAuth(a Authenticator, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		userID, ok := a.Validate(token)
		if !ok {
			writeError(w, http.StatusUnauthorized, "invalid or expired session")
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, userID)
		ctx = context.WithValue(ctx, tokenKey, token)
		next(w, r.WithContext(ctx))
	}
}

// bearerToken extracts the token from an `Authorization: Bearer <token>` header.
func bearerToken(r *http.Request) (string, bool) {
	const prefix = "Bearer "
	h := r.Header.Get("Authorization")
	if len(h) > len(prefix) && strings.EqualFold(h[:len(prefix)], prefix) {
		return strings.TrimSpace(h[len(prefix):]), true
	}
	return "", false
}

// userIDFrom / tokenFrom read values placed by requireAuth. They return "" if
// the handler wasn't wrapped (a programming error).
func userIDFrom(ctx context.Context) string {
	v, _ := ctx.Value(userIDKey).(string)
	return v
}

func tokenFrom(ctx context.Context) string {
	v, _ := ctx.Value(tokenKey).(string)
	return v
}
