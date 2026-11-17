package memstore

import (
	"sync"
	"testing"
	"time"
)

func TestStartCodeGuard_replacesThenLocks(t *testing.T) {
	g := NewStartCodeGuard()
	now := time.Date(2026, 11, 17, 10, 0, 0, 0, time.UTC)
	g.now = func() time.Time { return now }

	for code := 1; code <= MaxStartCodeResets; code++ {
		for i := 1; i < MaxStartCodeFailures; i++ {
			if replace, locked := g.RecordFailure("r1"); replace || locked != 0 {
				t.Fatalf("code %d, miss %d: replace %v, locked %v; want just a miss", code, i, replace, locked)
			}
		}
		replace, locked := g.RecordFailure("r1")
		if !replace {
			t.Fatalf("code %d: the %dth miss didn't use the code up", code, MaxStartCodeFailures)
		}
		if last := code == MaxStartCodeResets; (locked != 0) != last {
			t.Fatalf("code %d: locked for %v, want a lock only after the last code", code, locked)
		}
	}
	if ok, wait := g.Allow("r1"); ok || wait != StartCodeLockDuration {
		t.Fatalf("Allow while locked = %v, %v; want false, %v", ok, wait, StartCodeLockDuration)
	}
	if ok, _ := g.Allow("other-ride"); !ok {
		t.Error("another ride was locked too")
	}

	now = now.Add(StartCodeLockDuration)
	if ok, _ := g.Allow("r1"); !ok {
		t.Fatal("still locked after the lock ran out")
	}
	if replace, _ := g.RecordFailure("r1"); replace {
		t.Error("the count didn't start again after the lock")
	}
	g.Succeed("r1")
	if len(g.rides) != 0 {
		t.Errorf("%d rides remembered after the start", len(g.rides))
	}
}

func TestStartCodeGuard_concurrentMissesCountEveryOne(t *testing.T) {
	g := NewStartCodeGuard()
	total := MaxStartCodeFailures * MaxStartCodeResets
	var (
		wg    sync.WaitGroup
		mu    sync.Mutex
		locks int
	)
	for range total {
		wg.Go(func() {
			if _, locked := g.RecordFailure("r1"); locked != 0 {
				mu.Lock()
				locks++
				mu.Unlock()
			}
		})
	}
	wg.Wait()
	if locks != 1 {
		t.Errorf("%d misses locked the ride %d times, want once", total, locks)
	}
}
