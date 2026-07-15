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
	if _, ok := repo.stored[sess.Token]; !ok {
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
	if _, ok := repo.stored[sess.Token]; ok {
		t.Fatal("revoked token should be gone from the durable store")
	}
}

func TestSessionService_WarmLoadsCacheFromDB(t *testing.T) {
	repo, cache := newFakeSessionRepo(), newFakeSessionCache()
	// Simulate rows already in the DB from before a restart.
	now := time.Now()
	repo.stored["t1"] = domain.Session{Token: "t1", UserID: "u1", ExpiresAt: now.Add(time.Hour)}
	repo.stored["t2"] = domain.Session{Token: "t2", UserID: "u2", ExpiresAt: now.Add(time.Hour)}

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
