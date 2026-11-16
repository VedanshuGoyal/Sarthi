package service

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

// fakeRetentionStore records the cutoffs it was asked to delete before.
type fakeRetentionStore struct {
	mu             sync.Mutex
	sessionCutoffs []time.Time
	checkCutoffs   []time.Time
	sessionsErr    error
}

func (f *fakeRetentionStore) DeleteSessionsExpiredBefore(_ context.Context, cutoff time.Time) (int64, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sessionCutoffs = append(f.sessionCutoffs, cutoff)
	return 3, f.sessionsErr
}

func (f *fakeRetentionStore) DeleteKYCChecksBefore(_ context.Context, cutoff time.Time) (int64, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.checkCutoffs = append(f.checkCutoffs, cutoff)
	return 5, nil
}

func (f *fakeRetentionStore) sweeps() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.checkCutoffs)
}

type fakeFinisher struct {
	n   int
	err error
}

func (f fakeFinisher) FinishErasedDocuments(context.Context) (int, error) { return f.n, f.err }

func TestRetention_SweepUsesEachRulesCutoff(t *testing.T) {
	now := time.Date(2026, 11, 17, 3, 0, 0, 0, time.UTC)
	store := &fakeRetentionStore{}
	s := NewRetentionService(store, fakeFinisher{n: 2})
	s.now = func() time.Time { return now }

	report, err := s.Sweep(context.Background())
	if err != nil {
		t.Fatalf("Sweep: %v", err)
	}
	if want := now.AddDate(0, 0, -7); len(store.sessionCutoffs) != 1 || !store.sessionCutoffs[0].Equal(want) {
		t.Errorf("sessions cut off at %v, want %v", store.sessionCutoffs, want)
	}
	if want := now.AddDate(0, 0, -180); len(store.checkCutoffs) != 1 || !store.checkCutoffs[0].Equal(want) {
		t.Errorf("KYC checks cut off at %v, want %v", store.checkCutoffs, want)
	}
	if report.Sessions != 3 || report.KYCChecks != 5 || report.ErasedDocuments != 2 {
		t.Errorf("report = %+v", report)
	}
}

// One failing rule must not stop the others, and its error must surface.
func TestRetention_AFailingRuleDoesNotStopTheRest(t *testing.T) {
	store := &fakeRetentionStore{sessionsErr: errors.New("sessions: db down")}
	bucket := errors.New("bucket down")
	s := NewRetentionService(store, fakeFinisher{err: bucket})

	_, err := s.Sweep(context.Background())
	if !errors.Is(err, store.sessionsErr) || !errors.Is(err, bucket) {
		t.Errorf("err = %v, want both failures joined", err)
	}
	if len(store.checkCutoffs) != 1 {
		t.Error("the KYC check rule didn't run after the sessions rule failed")
	}
}

func TestRetention_WorksWithoutAnErasureFinisher(t *testing.T) {
	s := NewRetentionService(&fakeRetentionStore{}, nil)
	if _, err := s.Sweep(context.Background()); err != nil {
		t.Fatalf("Sweep: %v", err)
	}
}

func TestRetention_RunSweepsOnStartAndEachIntervalUntilCancelled(t *testing.T) {
	store := &fakeRetentionStore{}
	s := NewRetentionService(store, nil)
	s.every = time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		s.Run(ctx)
		close(done)
	}()

	deadline := time.Now().Add(5 * time.Second)
	for store.sweeps() < 3 {
		if time.Now().After(deadline) {
			t.Fatalf("only %d sweeps ran", store.sweeps())
		}
		time.Sleep(time.Millisecond)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run didn't return after its context was cancelled")
	}
}
