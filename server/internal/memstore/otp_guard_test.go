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
	g.maxSends = 100 // isolate the resend lock from the SMS cap
	const phone = "+919876543210"
	g.BeginSend(phone)
	for range MaxOTPResends {
		g.Resend(phone)
	}
	if ok, _ := g.Resend(phone); ok {
		t.Fatal("expected lockout after the cap")
	}

	// Restarting the flow (a fresh code) clears the resend lock right away,
	// within the SMS cap (see TestOTPGuard_SendCapBindsAcrossRestarts).
	g.BeginSend(phone)
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

func TestOTPGuard_SendCapBindsAcrossRestarts(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"

	// Restarting the flow used to reset every limit; now each fresh code
	// counts against the number's SMS allowance.
	for i := 1; i <= MaxOTPSends; i++ {
		if ok, _ := g.BeginSend(phone); !ok {
			t.Fatalf("send %d should be allowed", i)
		}
	}
	ok, retry := g.BeginSend(phone)
	if ok {
		t.Fatal("a send past the cap should be refused")
	}
	if retry <= 0 || retry > OTPSendWindow {
		t.Fatalf("retryAfter should be within the send window, got %v", retry)
	}

	// Once the oldest send ages out, one more is allowed.
	clk = clk.Add(OTPSendWindow + time.Second)
	if ok, _ := g.BeginSend(phone); !ok {
		t.Fatal("a send should be allowed after the window passes")
	}
}

func TestOTPGuard_ResendsCountTowardSendCap(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"
	g.BeginSend(phone)
	for range MaxOTPResends {
		g.Resend(phone)
	}
	// 1 fresh + 3 resends = 4 SMS; one fresh code is left this hour.
	if ok, _ := g.BeginSend(phone); !ok {
		t.Fatal("the fifth SMS should be allowed")
	}
	if ok, _ := g.Resend(phone); ok {
		t.Fatal("a resend past the SMS cap should be refused")
	}
}

func TestOTPGuard_RegistrationPass(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	const phone = "+919876543210"

	if g.ConsumeVerified(phone) {
		t.Fatal("no pass without a verified code")
	}
	g.BeginSend(phone)
	if g.ConsumeVerified(phone) {
		t.Fatal("sending a code is not verifying it")
	}

	g.Succeed(phone)
	if !g.ConsumeVerified(phone) {
		t.Fatal("a verified code should grant a pass")
	}
	if g.ConsumeVerified(phone) {
		t.Fatal("a pass is single-use")
	}

	g.Succeed(phone)
	clk = clk.Add(OTPVerifiedTTL + time.Second)
	if g.ConsumeVerified(phone) {
		t.Fatal("a pass expires after OTPVerifiedTTL")
	}

	g.Succeed(phone)
	g.BeginSend(phone)
	if g.ConsumeVerified(phone) {
		t.Fatal("requesting a new code drops an unused pass")
	}
}

func TestOTPGuard_SweepKeepsLiveSessions(t *testing.T) {
	clk := time.Now()
	g := newTestGuard(&clk)
	g.BeginSend("+919876543210")
	g.Succeed("+919876543211")
	g.sessions["+919876543212"] = &otpSession{}

	g.mu.Lock()
	g.sweep(clk)
	g.mu.Unlock()
	if _, ok := g.sessions["+919876543212"]; ok {
		t.Fatal("an idle session should be swept")
	}
	for _, phone := range []string{"+919876543210", "+919876543211"} {
		if _, ok := g.sessions[phone]; !ok {
			t.Fatalf("session %s holds a send or a pass and must stay", phone)
		}
	}
}
