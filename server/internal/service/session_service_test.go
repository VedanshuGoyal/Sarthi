package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

// fakeSessionRepo / fakeSessionCache are minimal in-memory doubles.
type fakeSessionRepo struct {
	stored    map[string]domain.Session
	createErr error
	deleteErr error
}

func newFakeSessionRepo() *fakeSessionRepo {
	return &fakeSessionRepo{stored: map[string]domain.Session{}}
}

func (r *fakeSessionRepo) Create(_ context.Context, s domain.Session) error {
	if r.createErr != nil {
		return r.createErr
	}
	r.stored[s.Token] = s
	return nil
}

func (r *fakeSessionRepo) Delete(_ context.Context, token string) error {
	delete(r.stored, token)
	return nil
}

func (r *fakeSessionRepo) DeleteForUser(_ context.Context, userID string) error {
	if r.deleteErr != nil {
		return r.deleteErr
	}
	for k, s := range r.stored {
		if s.UserID == userID {
			delete(r.stored, k)
		}
	}
	return nil
}

func (r *fakeSessionRepo) ListActive(context.Context) ([]domain.Session, error) {
	out := make([]domain.Session, 0, len(r.stored))
	for _, s := range r.stored {
		out = append(out, s)
	}
	return out, nil
}

type fakeSessionCache struct {
	m map[string]domain.Session
}

func newFakeSessionCache() *fakeSessionCache {
	return &fakeSessionCache{m: map[string]domain.Session{}}
}

func (c *fakeSessionCache) Put(s domain.Session) { c.m[s.Token] = s }
func (c *fakeSessionCache) Delete(token string)  { delete(c.m, token) }
func (c *fakeSessionCache) Get(token string) (domain.Session, bool) {
	s, ok := c.m[token]
	return s, ok
}
func (c *fakeSessionCache) DeleteUser(userID string) int {
	n := 0
	for k, s := range c.m {
		if s.UserID == userID {
			delete(c.m, k)
			n++
		}
	}
	return n
}
func (c *fakeSessionCache) Load(sessions []domain.Session) {
	c.m = map[string]domain.Session{}
	for _, s := range sessions {
		c.m[s.Token] = s
	}
}

func TestSessionService_IssueWritesThroughAndValidates(t *testing.T) {
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	s := NewSessionService(repo, cache)

	sess, err := s.Issue(context.Background(), "u1")
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	if sess.Token == "" || sess.UserID != "u1" {
		t.Fatalf("bad session: %+v", sess)
	}
	if sess.ExpiresAt.Before(sess.CreatedAt) {
		t.Fatal("session should expire after it is created")
	}
	// Durable store and cache both hold it.
	if _, ok := repo.stored[sess.Token]; ok {
		t.Fatal("the raw token must never be stored")
	}
	if _, ok := repo.stored[tokenKey(sess.Token)]; !ok {
		t.Fatal("session not persisted to the durable store")
	}
	// Validation reads from the cache.
	userID, ok := s.Validate(sess.Token)
	if !ok || userID != "u1" {
		t.Fatalf("Validate = (%q, %v), want (u1, true)", userID, ok)
	}
	if _, ok := s.Validate("garbage"); ok {
		t.Fatal("unknown token should not validate")
	}

	// Tokens are unique per issue.
	sess2, _ := s.Issue(context.Background(), "u1")
	if sess2.Token == sess.Token {
		t.Fatal("each Issue must mint a distinct token")
	}
}

func TestSessionService_IssueDoesNotCacheOnDBFailure(t *testing.T) {
	repo := newFakeSessionRepo()
	repo.createErr = errors.New("db down")
	cache := newFakeSessionCache()
	s := NewSessionService(repo, cache)

	if _, err := s.Issue(context.Background(), "u1"); err == nil {
		t.Fatal("expected Issue to fail when the DB write fails")
	}
	if len(cache.m) != 0 {
		t.Fatal("must not hand out / cache a token that wasn't persisted")
	}
}

func TestSessionService_Revoke(t *testing.T) {
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	s := NewSessionService(repo, cache)

	sess, _ := s.Issue(context.Background(), "u1")
	if err := s.Revoke(context.Background(), sess.Token); err != nil {
		t.Fatalf("Revoke: %v", err)
	}
	if _, ok := s.Validate(sess.Token); ok {
		t.Fatal("revoked token should not validate")
	}
	if _, ok := repo.stored[tokenKey(sess.Token)]; ok {
		t.Fatal("revoked token should be gone from the durable store")
	}
}

func TestSessionService_WarmLoadsCacheFromDB(t *testing.T) {
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	// Simulate rows already in the DB from before a restart.
	now := time.Now()
	// Rows hold token hashes (see tokenKey), as migration 0020 left them.
	repo.stored[tokenKey("t1")] = domain.Session{Token: tokenKey("t1"), UserID: "u1", ExpiresAt: now.Add(time.Hour)}
	repo.stored[tokenKey("t2")] = domain.Session{Token: tokenKey("t2"), UserID: "u2", ExpiresAt: now.Add(time.Hour)}

	s := NewSessionService(repo, cache)
	n, err := s.Warm(context.Background())
	if err != nil {
		t.Fatalf("Warm: %v", err)
	}
	if n != 2 {
		t.Fatalf("warmed %d, want 2", n)
	}
	if id, ok := s.Validate("t1"); !ok || id != "u1" {
		t.Fatal("token issued before restart should validate after warming")
	}
}

func TestSessionService_RevokeAllEndsEveryDeviceOfOneUser(t *testing.T) {
	ctx := context.Background()
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	s := NewSessionService(repo, cache)
	phone, tablet := mustIssue(t, s, "u1"), mustIssue(t, s, "u1")
	other := mustIssue(t, s, "u2")

	if err := s.RevokeAll(ctx, "u1"); err != nil {
		t.Fatalf("RevokeAll: %v", err)
	}
	for _, tok := range []string{phone, tablet} {
		if _, ok := s.Validate(tok); ok {
			t.Error("a token of the erased user still validates")
		}
		if _, ok := repo.stored[tokenKey(tok)]; ok {
			t.Error("a session of the erased user is still in the durable store")
		}
	}
	if id, ok := s.Validate(other); !ok || id != "u2" {
		t.Error("another user's session was revoked too")
	}
}

func TestSessionService_RevokeAllClearsTheCacheEvenWhenTheStoreFails(t *testing.T) {
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	s := NewSessionService(repo, cache)
	tok := mustIssue(t, s, "u1")
	repo.deleteErr = errors.New("db down")

	if err := s.RevokeAll(context.Background(), "u1"); err == nil {
		t.Fatal("RevokeAll hid the store's error")
	}
	if _, ok := s.Validate(tok); ok {
		t.Error("the token still works while the store is down")
	}
}

func mustIssue(t *testing.T, s *SessionService, userID string) string {
	t.Helper()
	sess, err := s.Issue(context.Background(), userID)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	return sess.Token
}
