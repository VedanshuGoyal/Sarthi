package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// DefaultSessionTTL is how long an issued token stays valid.
const DefaultSessionTTL = 30 * 24 * time.Hour

// tokenBytes is the entropy of an opaque session token (256 bits).
const tokenBytes = 32

// SessionRepo is the durable session store (PostgreSQL). Defined consumer-side
// so the service stays testable.
type SessionRepo interface {
	Create(ctx context.Context, s domain.Session) error
	Delete(ctx context.Context, token string) error
	ListActive(ctx context.Context) ([]domain.Session, error)
}

// SessionCache is the hot, in-memory session index (memstore). Validation reads
// from here so authenticated requests never touch the database.
type SessionCache interface {
	Put(s domain.Session)
	Get(token string) (domain.Session, bool)
	Delete(token string)
	Load(sessions []domain.Session)
}

// SessionService issues and validates opaque bearer tokens. On Issue it writes
// through to the durable store (source of truth) and the cache (hot path);
// Validate reads only the cache; Warm rebuilds the cache from the store on boot.
type SessionService struct {
	repo  SessionRepo
	cache SessionCache
	ttl   time.Duration
	now   func() time.Time // seam for tests
}

// NewSessionService constructs the service over a durable store and a cache.
func NewSessionService(repo SessionRepo, cache SessionCache) *SessionService {
	return &SessionService{repo: repo, cache: cache, ttl: DefaultSessionTTL, now: time.Now}
}

// Issue mints a new session for userID and persists it to both the durable
// store and the cache. It satisfies [TokenIssuer].
func (s *SessionService) Issue(ctx context.Context, userID string) (domain.Session, error) {
	token, err := newToken()
	if err != nil {
		return domain.Session{}, err
	}
	now := s.now()
	sess := domain.Session{
		Token:     token,
		UserID:    userID,
		CreatedAt: now,
		ExpiresAt: now.Add(s.ttl),
	}
	// Only the token's hash is stored and cached; the raw token goes back to
	// the client and nowhere else. Write the durable copy first: if the DB
	// write fails we never hand out a token that wouldn't survive a restart.
	stored := sess
	stored.Token = tokenKey(token)
	if err := s.repo.Create(ctx, stored); err != nil {
		return domain.Session{}, err
	}
	s.cache.Put(stored)
	return sess, nil
}

// Validate returns the user id for a token, reading only the cache (no DB hit).
func (s *SessionService) Validate(token string) (userID string, ok bool) {
	sess, ok := s.cache.Get(tokenKey(token))
	if !ok {
		return "", false
	}
	return sess.UserID, true
}

// Revoke deletes a session from both stores (logout). Unknown tokens are a
// no-op.
func (s *SessionService) Revoke(ctx context.Context, token string) error {
	key := tokenKey(token)
	if err := s.repo.Delete(ctx, key); err != nil {
		return err
	}
	s.cache.Delete(key)
	return nil
}

// Warm loads every still-valid session from the durable store into the cache.
// Call it once on startup so tokens issued before a restart keep working.
func (s *SessionService) Warm(ctx context.Context) (int, error) {
	sessions, err := s.repo.ListActive(ctx)
	if err != nil {
		return 0, err
	}
	s.cache.Load(sessions)
	return len(sessions), nil
}

// tokenKey is what the database and cache hold in place of a bearer token:
// its SHA-256, hex-encoded. A dump or backup of the sessions tables then holds
// no working credentials. Migration 0020 converted tokens issued before.
func tokenKey(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// newToken returns a URL-safe, high-entropy opaque token.
func newToken() (string, error) {
	b := make([]byte, tokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generating session token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
