package memstore

import (
	"sync"
	"time"
)

// Start-code limits. A ride's 4-digit code is what lets the driver start
// the trip, so wrong guesses are capped per ride, across code changes.
const (
	// MaxStartCodeFailures is how many wrong codes use up one code; the
	// ride then gets a new one.
	MaxStartCodeFailures = 5
	// MaxStartCodeResets is how many codes may be used up before the ride is
	// locked: 15 guesses in all, against odds of 1 in 10,000 each.
	MaxStartCodeResets = 3
	// StartCodeLockDuration is how long a locked ride refuses every code,
	// right or wrong. Then the count starts again.
	StartCodeLockDuration = 15 * time.Minute
)

type startCodeState struct {
	failures    int // wrong codes against the current code
	resets      int // codes used up since the last lock
	lockedUntil time.Time
}

// StartCodeGuard caps wrong start-code attempts per ride, in memory. Unlike
// [OTPGuard], nothing short of a correct code resets it: a new code (after
// a reset, or the ride being released and accepted again) keeps the count,
// so guessing can't be stretched out by cycling codes.
//
// State is hot and rebuildable: a restart forgets the counts, which only
// gives a guesser a fresh 15 tries. Entries exist only for rides that had a
// wrong code and go when the ride starts.
type StartCodeGuard struct {
	mu    sync.Mutex
	rides map[string]*startCodeState
	now   func() time.Time // seam for tests

	maxFailures int
	maxResets   int
	lockFor     time.Duration
}

// NewStartCodeGuard returns a guard with the package limits.
func NewStartCodeGuard() *StartCodeGuard {
	return &StartCodeGuard{
		rides:       make(map[string]*startCodeState),
		now:         time.Now,
		maxFailures: MaxStartCodeFailures,
		maxResets:   MaxStartCodeResets,
		lockFor:     StartCodeLockDuration,
	}
}

// Allow reports whether a code may be tried for ride now; while it's locked,
// retryAfter is how long until it may.
func (g *StartCodeGuard) Allow(ride string) (ok bool, retryAfter time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.rides[ride]
	if s == nil {
		return true, 0
	}
	if wait := s.lockedUntil.Sub(g.now()); wait > 0 {
		return false, wait
	}
	return true, 0
}

// RecordFailure counts a wrong code for ride. replace is true when that used
// up the current code, which the caller must then replace; lockedFor is
// non-zero when it also locked the ride, for that long.
func (g *StartCodeGuard) RecordFailure(ride string) (replace bool, lockedFor time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.rides[ride]
	if s == nil {
		s = &startCodeState{}
		g.rides[ride] = s
	}
	s.failures++
	if s.failures < g.maxFailures {
		return false, 0
	}
	s.failures = 0
	s.resets++
	if s.resets < g.maxResets {
		return true, 0
	}
	s.resets = 0
	s.lockedUntil = g.now().Add(g.lockFor)
	return true, g.lockFor
}

// Succeed forgets ride once it has started.
func (g *StartCodeGuard) Succeed(ride string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.rides, ride)
}
