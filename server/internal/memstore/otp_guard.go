package memstore

import (
	"sync"
	"time"
)

// OTP abuse-prevention limits. They guard a single OTP "session" — the window
// between requesting a code and successfully verifying it.
const (
	// MaxOTPResends is how many times a code may be re-sent within one session
	// before the number is locked out.
	MaxOTPResends = 3
	// MaxOTPVerifyFailures is how many wrong codes are tolerated before the
	// session's OTP is invalidated and a new one must be requested.
	MaxOTPVerifyFailures = 5
	// OTPLockDuration is how long resends are blocked after the resend cap is
	// hit. Waiting it out — or restarting the flow with a fresh code — clears
	// the lock.
	OTPLockDuration = 30 * time.Minute
)

// otpSession is the per-number counter set for one OTP session.
type otpSession struct {
	resends     int       // resend-endpoint hits so far
	failures    int       // wrong-code verifications so far
	lockedUntil time.Time // resend-lockout expiry; zero when not locked
	invalidated bool      // OTP killed after too many wrong codes
}

func (s *otpSession) locked(now time.Time) bool {
	return !s.lockedUntil.IsZero() && s.lockedUntil.After(now)
}

// OTPGuard is a concurrency-safe, in-memory rate limiter for the OTP flow,
// keyed by phone number. It enforces Sarthi's own per-session caps — max
// resends, max failed verifications, and a lockout — independently of whatever
// the SMS provider does. Every operation mutates, so it uses a plain Mutex
// rather than the RWMutex the read-heavy caches use.
//
// State is hot and rebuildable: losing it on restart only resets a few
// in-flight counters, never anything durable. A cleared or expired session is
// handled lazily on next touch; there is no active sweep.
type OTPGuard struct {
	mu       sync.Mutex
	sessions map[string]*otpSession
	now      func() time.Time // seam for tests

	maxResends  int
	maxFailures int
	lockFor     time.Duration
}

// NewOTPGuard returns a guard configured with the package limits.
func NewOTPGuard() *OTPGuard {
	return &OTPGuard{
		sessions:    make(map[string]*otpSession),
		now:         time.Now,
		maxResends:  MaxOTPResends,
		maxFailures: MaxOTPVerifyFailures,
		lockFor:     OTPLockDuration,
	}
}

// Begin starts (or restarts) an OTP session for phone, clearing every counter
// and any lock. Call it whenever a fresh code is issued (RequestOTP), so
// restarting the login flow is the documented escape hatch from a lockout or
// an invalidated OTP.
func (g *OTPGuard) Begin(phone string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.sessions[phone] = &otpSession{}
}

// Resend registers a resend attempt. It returns ok=false when the session is
// locked — either it already was, or this attempt hit the cap — along with how
// long until the lock clears (retryAfter). On ok=true the attempt is counted;
// the caller may dispatch the SMS.
func (g *OTPGuard) Resend(phone string) (ok bool, retryAfter time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := g.now()
	s := g.liveSession(phone, now)
	if s.locked(now) {
		return false, s.lockedUntil.Sub(now)
	}
	s.resends++
	if s.resends >= g.maxResends {
		// Allowance spent: serve the final code, then lock further resends.
		s.lockedUntil = now.Add(g.lockFor)
	}
	return true, 0
}

// CheckVerify reports whether a verification may proceed. It returns false once
// the OTP has been invalidated by too many wrong codes, so the transport can
// reject the attempt before consulting the provider.
func (g *OTPGuard) CheckVerify(phone string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.sessions[phone]
	return s == nil || !s.invalidated
}

// RecordFailure counts a wrong-code verification. invalidated=true means the
// cap was reached and the OTP is now dead until a new session Begins.
func (g *OTPGuard) RecordFailure(phone string) (invalidated bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.session(phone)
	s.failures++
	if s.failures >= g.maxFailures {
		s.invalidated = true
	}
	return s.invalidated
}

// Succeed clears a session after a correct code, freeing its memory. It is not
// required for correctness — a stale session is harmless — but keeps the map
// from growing with completed flows.
func (g *OTPGuard) Succeed(phone string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.sessions, phone)
}

// liveSession returns phone's session, creating a fresh one if none exists or
// if a previous lockout has since expired. Resetting on an expired lock is what
// makes "wait 30 minutes" restore the resend allowance. Callers must hold mu.
func (g *OTPGuard) liveSession(phone string, now time.Time) *otpSession {
	s := g.sessions[phone]
	if s == nil || (!s.lockedUntil.IsZero() && !s.lockedUntil.After(now)) {
		s = &otpSession{}
		g.sessions[phone] = s
	}
	return s
}

// session returns phone's session, creating an empty one if absent (e.g. after
// a restart dropped it). Callers must hold mu.
func (g *OTPGuard) session(phone string) *otpSession {
	s := g.sessions[phone]
	if s == nil {
		s = &otpSession{}
		g.sessions[phone] = s
	}
	return s
}
