package memstore

import (
	"sync"
	"time"
)

// Daily SMS spend for the whole service, across both apps.
const (
	// MaxDailySMS is how many OTP texts the service sends per SMSWindow.
	MaxDailySMS = 1500
	SMSWindow   = 24 * time.Hour
)

// SMSBudget caps how many SMS the whole service sends per window: a fixed
// window that starts at the first text after the last one ended. It counts
// only texts actually dispatched (the auth services spend from it after the
// per-number guard allows a send), so junk requests can't use it up. Safe
// for concurrent use; a restart forgets the count, like every memstore.
type SMSBudget struct {
	mu     sync.Mutex
	max    int
	window time.Duration
	now    func() time.Time
	start  time.Time
	spent  int
}

// NewSMSBudget allows max texts per window.
func NewSMSBudget(max int, window time.Duration) *SMSBudget {
	return &SMSBudget{max: max, window: window, now: time.Now}
}

// Spend takes one text from the budget. ok=false, with how long until the
// window resets, means the budget is used up and nothing was taken.
func (b *SMSBudget) Spend() (ok bool, retryAfter time.Duration) {
	b.mu.Lock()
	defer b.mu.Unlock()
	now := b.now()
	if b.start.IsZero() || now.Sub(b.start) >= b.window {
		b.start, b.spent = now, 0
	}
	if b.spent >= b.max {
		return false, b.start.Add(b.window).Sub(now)
	}
	b.spent++
	return true, 0
}
