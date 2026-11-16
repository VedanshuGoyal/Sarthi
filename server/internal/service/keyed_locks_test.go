package service

import (
	"sync"
	"sync/atomic"
	"testing"
)

func TestKeyedLocks_serialisesOneKeyAndForgetsIt(t *testing.T) {
	var (
		locks   keyedLocks
		inside  atomic.Int32
		maxSeen atomic.Int32
		wg      sync.WaitGroup
	)
	for range 50 {
		wg.Go(func() {
			unlock := locks.lock("driver-1")
			n := inside.Add(1)
			for {
				m := maxSeen.Load()
				if n <= m || maxSeen.CompareAndSwap(m, n) {
					break
				}
			}
			inside.Add(-1)
			unlock()
		})
	}
	wg.Wait()
	if maxSeen.Load() != 1 {
		t.Errorf("%d goroutines held the same key at once", maxSeen.Load())
	}
	if len(locks.locks) != 0 {
		t.Errorf("%d keys left behind after every holder unlocked", len(locks.locks))
	}

	// Different keys don't wait for each other.
	unlockA := locks.lock("a")
	done := make(chan struct{})
	go func() { locks.lock("b")(); close(done) }()
	<-done
	unlockA()
}
