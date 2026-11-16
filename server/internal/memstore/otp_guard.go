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
	// hit. Waiting it out — or restarting the flow with a fresh code, while the
	// send cap allows — clears the lock.
	OTPLockDuration = 30 * time.Minute
	// MaxOTPSends caps how many SMS (fresh codes plus resends) one number can
	// trigger per OTPSendWindow. Every send is a paid SMS to someone's phone,
	// so this binds across restarted flows, unlike the per-session caps.
	MaxOTPSends   = 5
	OTPSendWindow = time.Hour
	// OTPVerifiedTTL is how long a correct code for a number without an account
	// lets that number register. Registration must present this proof, or
	// anyone could create (and later share) an account on someone else's number.
	OTPVerifiedTTL = 30 * time.Minute
	// maxIdleSessions is the map size at which Begin sweeps finished sessions.
	maxIdleSessions = 10_000
)

// otpSession is the per-number counter set for one OTP session.
type otpSession struct {
	resends       int         // resend-endpoint hits so far
	failures      int         // wrong-code verifications so far
	lockedUntil   time.Time   // resend-lockout expiry; zero when not locked
	invalidated   bool        // OTP killed after too many wrong codes
	sends         []time.Time // SMS sent within the last OTPSendWindow
	verifiedUntil time.Time   // a correct code may register until then
}

func (s *otpSession) locked(now time.Time) bool {
	return !s.lockedUntil.IsZero() && s.lockedUntil.After(now)
}

// sendAllowance drops sends older than window and reports whether another is
// allowed; when not, retryAfter is when the oldest one ages out.
func (s *otpSession) sendAllowance(now time.Time, max int, window time.Duration) (ok bool, retryAfter time.Duration) {
	kept := s.sends[:0]
	for _, t := range s.sends {
		if now.Sub(t) < window {
			kept = append(kept, t)
		}
	}
	s.sends = kept
	if len(s.sends) < max {
		return true, 0
	}
	return false, s.sends[0].Add(window).Sub(now)
}

// idle reports whether the session holds nothing worth keeping.
func (s *otpSession) idle(now time.Time, window time.Duration) bool {
	if s.locked(now) || s.verifiedUntil.After(now) {
		return false
	}
	for _, t := range s.sends {
		if now.Sub(t) < window {
			return false
		}
	}
	return true
}

// OTPGuard is a concurrency-safe, in-memory rate limiter for the OTP flow,
// keyed by phone number. It enforces Sarthi's own per-session caps — max
// resends, max failed verifications, and a lockout — independently of whatever
// the SMS provider does. Every operation mutates, so it uses a plain Mutex
// rather than the RWMutex the read-heavy caches use.
//
// State is hot and rebuildable: losing it on restart only resets a few
// in-flight counters and unused registration passes (the user verifies again),
// never anything durable. Finished sessions are swept lazily once the map
// grows large.
type OTPGuard struct {
	mu       sync.Mutex
	sessions map[string]*otpSession
	now      func() time.Time // seam for tests

	maxResends  int
	maxFailures int
	lockFor     time.Duration
	maxSends    int
	sendWindow  time.Duration
	verifiedTTL time.Duration
}

// NewOTPGuard returns a guard configured with the package limits.
func NewOTPGuard() *OTPGuard {
	return &OTPGuard{
		sessions:    make(map[string]*otpSession),
		now:         time.Now,
		maxResends:  MaxOTPResends,
		maxFailures: MaxOTPVerifyFailures,
		lockFor:     OTPLockDuration,
		maxSends:    MaxOTPSends,
		sendWindow:  OTPSendWindow,
		verifiedTTL: OTPVerifiedTTL,
	}
}

// Begin unconditionally starts a fresh session for key, clearing every
// counter, lock and pass. The ride start-code guard uses it; login flows use
// [OTPGuard.BeginSend], which also enforces the SMS cap.
func (g *OTPGuard) Begin(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.sessions[key] = &otpSession{}
}

// BeginSend starts (or restarts) an OTP session for phone when a fresh code is
// about to be sent (RequestOTP). It returns ok=false, with how long to wait,
// once the number has used its SMS allowance for the window. Otherwise it
// counts the send and clears the per-session counters, any resend lock and any
// unused registration pass, so restarting the flow still escapes a resend
// lockout or an invalidated OTP - but never past the send cap.
func (g *OTPGuard) BeginSend(phone string) (ok bool, retryAfter time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()

	now := g.now()
	if len(g.sessions) >= maxIdleSessions {
		g.sweep(now)
	}
	s := g.session(phone)
	if ok, retryAfter := s.sendAllowance(now, g.maxSends, g.sendWindow); !ok {
		return false, retryAfter
	}
	s.sends = append(s.sends, now)
	s.resends, s.failures, s.invalidated = 0, 0, false
	s.lockedUntil, s.verifiedUntil = time.Time{}, time.Time{}
	return true, 0
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
	if ok, retryAfter := s.sendAllowance(now, g.maxSends, g.sendWindow); !ok {
		return false, retryAfter
	}
	s.sends = append(s.sends, now)
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

// Succeed records a correct code: it clears the failure count and grants a
// registration pass for OTPVerifiedTTL (see [OTPGuard.ConsumeVerified]). The
// send history is kept, so logging in does not reset the SMS allowance.
func (g *OTPGuard) Succeed(phone string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.session(phone)
	s.failures, s.invalidated = 0, false
	s.verifiedUntil = g.now().Add(g.verifiedTTL)
}

// ConsumeVerified reports whether phone verified a correct code within
// OTPVerifiedTTL, and uses that pass up: one verification, one registration.
func (g *OTPGuard) ConsumeVerified(phone string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	s := g.sessions[phone]
	if s == nil || !s.verifiedUntil.After(g.now()) {
		return false
	}
	s.verifiedUntil = time.Time{}
	return true
}

// liveSession returns phone's session, creating one if none exists. A resend
// lock that has since expired is cleared along with the resend count, which
// is what makes "wait 30 minutes" restore the resend allowance; the send
// history stays. Callers must hold mu.
func (g *OTPGuard) liveSession(phone string, now time.Time) *otpSession {
	s := g.session(phone)
	if !s.lockedUntil.IsZero() && !s.lockedUntil.After(now) {
		s.lockedUntil = time.Time{}
		s.resends = 0
	}
	return s
}

// sweep drops sessions that no longer hold a lock, a pass or a recent send,
// so the map stays bounded by recent traffic. Callers must hold mu.
func (g *OTPGuard) sweep(now time.Time) {
	for phone, s := range g.sessions {
		if s.idle(now, g.sendWindow) {
			delete(g.sessions, phone)
		}
	}
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
