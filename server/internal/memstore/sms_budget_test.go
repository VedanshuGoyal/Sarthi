package memstore

import (
	"sync"
	"testing"
	"time"
)

func TestSMSBudget_capsTheWindowThenResets(t *testing.T) {
	now := time.Date(2026, 11, 17, 9, 0, 0, 0, time.UTC)
	b := NewSMSBudget(2, 24*time.Hour)
	b.now = func() time.Time { return now }

	for i := range 2 {
		if ok, _ := b.Spend(); !ok {
			t.Fatalf("text %d refused within the budget", i+1)
		}
	}
	now = now.Add(time.Hour)
	ok, retry := b.Spend()
	if ok || retry != 23*time.Hour {
		t.Errorf("third text: ok=%v retry=%v, want refused for 23h", ok, retry)
	}
	now = now.Add(23 * time.Hour)
	if ok, _ := b.Spend(); !ok {
		t.Error("a new window still refused")
	}
}

func TestSMSBudget_concurrentSpendsNeverOvershoot(t *testing.T) {
	b := NewSMSBudget(100, time.Hour)
	var (
		wg      sync.WaitGroup
		mu      sync.Mutex
		allowed int
	)
	for range 8 {
		wg.Go(func() {
			for range 50 {
				if ok, _ := b.Spend(); ok {
					mu.Lock()
					allowed++
					mu.Unlock()
				}
			}
		})
	}
	wg.Wait()
	if allowed != 100 {
		t.Errorf("allowed %d texts, want exactly 100", allowed)
	}
}
