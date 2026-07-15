package memstore

import (
	"testing"
	"time"
)

// newTestGuard returns a guard whose clock is driven by *clk, so tests advance
// time deterministically.
func newTestGuard(clk *time.Time) *OTPGuard {
	g := NewOTPGuard()
	g.now = func() time.Time { return *clk }
	return g
}

func TestOTPGuard_ResendCapThenLock(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.Begin(phone)

	// Three resends are allowed within one session.
	for i := 1; i <= MaxOTPResends; i++ {
		ok, retry := g.Resend(phone)
		if !ok {
			t.Fatalf("resend %d should be allowed", i)
		}
		if retry != 0 {
			t.Fatalf("allowed resend should have no retryAfter, got %v", retry)
		}
	}

	// The fourth is locked out for the lock duration.
	ok, retry := g.Resend(phone)
	if ok {
		t.Fatal("resend past the cap should be locked")
	}
	if retry <= 0 || retry > OTPLockDuration {
		t.Fatalf("retryAfter should be within the lock window, got %v", retry)
	}
}

func TestOTPGuard_LockClearsAfterWaiting(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.Begin(phone)
	for range MaxOTPResends {
		g.Resend(phone)
	}
	if ok, _ := g.Resend(phone); ok {
		t.Fatal("should be locked immediately after the cap")
	}

	// Waiting out the lockout restores the resend allowance.
	clk = clk.Add(OTPLockDuration + time.Second)
	if ok, retry := g.Resend(phone); !ok {
		t.Fatalf("resend should be allowed once the lock expires (retry %v)", retry)
	}
}

func TestOTPGuard_BeginResetsLockout(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.Begin(phone)
	for range MaxOTPResends {
		g.Resend(phone)
	}
	if ok, _ := g.Resend(phone); ok {
		t.Fatal("expected lockout after the cap")
	}

	// Restarting the flow (a fresh code) clears the lock right away.
	g.Begin(phone)
	if ok, _ := g.Resend(phone); !ok {
		t.Fatal("Begin should reset the resend allowance")
	}
}

func TestOTPGuard_VerifyFailuresInvalidate(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.Begin(phone)

	if !g.CheckVerify(phone) {
		t.Fatal("a fresh session should allow verification")
	}

	// The first four wrong codes are tolerated; the fifth invalidates the OTP.
	for i := 1; i < MaxOTPVerifyFailures; i++ {
		if invalidated := g.RecordFailure(phone); invalidated {
			t.Fatalf("failure %d should not invalidate yet", i)
		}
		if !g.CheckVerify(phone) {
			t.Fatalf("verification should still be allowed after %d failures", i)
		}
	}
	if invalidated := g.RecordFailure(phone); !invalidated {
		t.Fatal("the final failure should invalidate the OTP")
	}
	if g.CheckVerify(phone) {
		t.Fatal("verification should be rejected once invalidated")
	}

	// A waiting-out does not resurrect an invalidated OTP — only Begin does.
	clk = clk.Add(OTPLockDuration + time.Minute)
	if g.CheckVerify(phone) {
		t.Fatal("an invalidated OTP must stay dead until a new code is requested")
	}
	g.Begin(phone)
	if !g.CheckVerify(phone) {
		t.Fatal("Begin should clear the invalidation")
	}
}

func TestOTPGuard_SucceedClearsSession(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.Begin(phone)
	g.RecordFailure(phone)
	g.Succeed(phone)

	// After success the session is gone; a later verify is treated as fresh.
	if !g.CheckVerify(phone) {
		t.Fatal("a cleared session should allow verification")
	}
}
