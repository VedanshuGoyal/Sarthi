package memstore

import (
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func session(token, userID string, expiresAt time.Time) domain.Session {
	return domain.Session{Token: token, UserID: userID, CreatedAt: time.Now(), ExpiresAt: expiresAt}
}

func TestSessionCache_PutGetDelete(t *testing.T) {
	c := NewSessionCache()
	s := session("t1", "u1", time.Now().Add(time.Hour))

	if _, ok := c.Get("t1"); ok {
		t.Fatal("empty cache should not find a token")
	}
	c.Put(s)
	got, ok := c.Get("t1")
	if !ok || got.UserID != "u1" {
		t.Fatalf("Get = (%+v, %v), want the stored session", got, ok)
	}
	c.Delete("t1")
	if _, ok := c.Get("t1"); ok {
		t.Fatal("deleted token should be gone")
	}
}

func TestSessionCache_ExpiredReadsAsAbsent(t *testing.T) {
	c := NewSessionCache()
	c.Put(session("expired", "u1", time.Now().Add(-time.Minute)))

	if _, ok := c.Get("expired"); ok {
		t.Fatal("an expired session must not validate")
	}
}

func TestSessionCache_LoadReplacesContents(t *testing.T) {
	c := NewSessionCache()
	c.Put(session("old", "u0", time.Now().Add(time.Hour)))

	c.Load([]domain.Session{
		session("t1", "u1", time.Now().Add(time.Hour)),
		session("t2", "u2", time.Now().Add(time.Hour)),
	})

	if _, ok := c.Get("old"); ok {
		t.Fatal("Load should replace, not merge")
	}
	if _, ok := c.Get("t1"); !ok {
		t.Fatal("loaded session t1 should be present")
	}
	if c.Count() != 2 {
		t.Fatalf("Count = %d, want 2", c.Count())
	}
}

// TestSessionCache_Concurrent exercises the RWMutex under the race detector.
func TestSessionCache_Concurrent(t *testing.T) {
	c := NewSessionCache()
	const n = 200
	var wg sync.WaitGroup
	wg.Add(n)
	for i := range n {
		go func(i int) {
			defer wg.Done()
			tok := "t" + strconv.Itoa(i)
			c.Put(session(tok, "u"+strconv.Itoa(i), time.Now().Add(time.Hour)))
			c.Get(tok)
			c.Count()
		}(i)
	}
	wg.Wait()
	if c.Count() != n {
		t.Fatalf("Count = %d, want %d", c.Count(), n)
	}
}
