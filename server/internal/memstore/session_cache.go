package memstore

import (
	"sync"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// SessionCache is a concurrency-safe, in-memory index of live auth sessions,
// keyed by token. It is the hot path for request authentication: every
// authenticated request validates its bearer token here instead of hitting
// PostgreSQL. The durable store (repository.SessionRepository) remains the
// source of truth and is used to rebuild this cache on boot.
//
// Expiry is handled lazily: an expired token reads as absent from [Get] but is
// not actively swept (a production system would add a periodic sweep).
type SessionCache struct {
	mu      sync.RWMutex
	byToken map[string]domain.Session
	now     func() time.Time // seam for tests
}

// NewSessionCache returns an empty cache.
func NewSessionCache() *SessionCache {
	return &SessionCache{
		byToken: make(map[string]domain.Session),
		now:     time.Now,
	}
}

// Put stores (or replaces) a session.
func (c *SessionCache) Put(s domain.Session) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.byToken[s.Token] = s
}

// Get returns the session for a token and whether it is present and unexpired.
// An expired session is reported as absent.
func (c *SessionCache) Get(token string) (domain.Session, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	s, ok := c.byToken[token]
	if !ok || !s.ExpiresAt.After(c.now()) {
		return domain.Session{}, false
	}
	return s, true
}

// Delete removes a session (e.g. on logout). Unknown tokens are ignored.
func (c *SessionCache) Delete(token string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.byToken, token)
}

// DeleteUser removes every session of userID and returns how many went
// (account erasure). It scans the whole map: erasure is rare and the cache
// holds one entry per signed-in device, so a second index isn't worth
// keeping in step with Put, Delete and Load.
func (c *SessionCache) DeleteUser(userID string) int {
	c.mu.Lock()
	defer c.mu.Unlock()
	n := 0
	for token, s := range c.byToken {
		if s.UserID == userID {
			delete(c.byToken, token)
			n++
		}
	}
	return n
}

// Load replaces the cache contents with sessions (used to warm from the DB on
// boot). It is atomic from a reader's perspective.
func (c *SessionCache) Load(sessions []domain.Session) {
	fresh := make(map[string]domain.Session, len(sessions))
	for _, s := range sessions {
		fresh[s.Token] = s
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.byToken = fresh
}

// Count returns the number of cached sessions (including any not-yet-swept
// expired ones).
func (c *SessionCache) Count() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.byToken)
}
