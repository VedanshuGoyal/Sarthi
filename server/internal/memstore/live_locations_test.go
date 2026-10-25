package memstore

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func TestLiveLocations_latestFixWins(t *testing.T) {
	l := NewLiveLocations()
	if _, ok := l.Latest("d1"); ok {
		t.Fatal("empty store reported a fix")
	}
	at := time.Date(2026, 10, 25, 10, 0, 0, 0, time.UTC)
	l.Put("d1", domain.LiveLocation{Lat: 28.6, Lng: 77.2, UpdatedAt: at})
	l.Put("d1", domain.LiveLocation{Lat: 28.7, Lng: 77.3, UpdatedAt: at.Add(10 * time.Second)})

	got, ok := l.Latest("d1")
	if !ok || got.Lat != 28.7 || got.Lng != 77.3 {
		t.Fatalf("Latest = %+v, %v; want the second fix", got, ok)
	}
	if _, ok := l.Latest("d2"); ok {
		t.Error("another driver's fix leaked")
	}
}

func TestLiveLocations_concurrentPutAndRead(t *testing.T) {
	l := NewLiveLocations()
	var wg sync.WaitGroup
	for i := range 8 {
		wg.Add(2)
		id := fmt.Sprintf("d%d", i)
		go func() {
			defer wg.Done()
			for j := range 200 {
				l.Put(id, domain.LiveLocation{Lat: float64(j), UpdatedAt: time.Now()})
			}
		}()
		go func() {
			defer wg.Done()
			for range 200 {
				l.Latest(id)
			}
		}()
	}
	wg.Wait()
	for i := range 8 {
		if got, ok := l.Latest(fmt.Sprintf("d%d", i)); !ok || got.Lat != 199 {
			t.Errorf("d%d = %+v, %v; want the last fix", i, got, ok)
		}
	}
}
