package memstore

import (
	"strconv"
	"sync"
	"testing"
	"time"
)

func TestSessionCache_DeleteUserDropsOnlyThatUsersTokens(t *testing.T) {
	c := NewSessionCache()
	later := time.Now().Add(time.Hour)
	c.Put(session("phone", "u1", later))
	c.Put(session("tablet", "u1", later))
	c.Put(session("other", "u2", later))

	if n := c.DeleteUser("u1"); n != 2 {
		t.Fatalf("DeleteUser = %d, want 2", n)
	}
	for _, tok := range []string{"phone", "tablet"} {
		if _, ok := c.Get(tok); ok {
			t.Errorf("token %q of the deleted user is still cached", tok)
		}
	}
	if _, ok := c.Get("other"); !ok {
		t.Error("another user's token went too")
	}
	if n := c.DeleteUser("u1"); n != 0 {
		t.Errorf("second DeleteUser = %d, want 0", n)
	}
}

// Erasing one user while others sign in and authenticate, under -race.
func TestSessionCache_DeleteUserConcurrentWithTraffic(t *testing.T) {
	c := NewSessionCache()
	later := time.Now().Add(time.Hour)
	const n = 100
	for i := range n {
		c.Put(session("erased-"+strconv.Itoa(i), "erased", later))
	}
	var wg sync.WaitGroup
	wg.Add(n + 1)
	for i := range n {
		go func(i int) {
			defer wg.Done()
			tok := "t" + strconv.Itoa(i)
			c.Put(session(tok, "u"+strconv.Itoa(i), later))
			c.Get(tok)
		}(i)
	}
	go func() {
		defer wg.Done()
		c.DeleteUser("erased")
	}()
	wg.Wait()
	if got := c.Count(); got != n {
		t.Fatalf("Count = %d, want %d (every erased token gone, every other kept)", got, n)
	}
}
