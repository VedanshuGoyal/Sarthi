package service

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/sarthi/server/internal/domain"
)

func TestNotify_PayoutSent(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	_ = tokens.SaveForDriver(context.Background(), "d1", "tok-d1")
	_ = tokens.SaveForDriver(context.Background(), "d2", "tok-d2")

	svc.PayoutSent(context.Background(), domain.DriverPayout{
		ID: "p1", DriverID: "d1", AmountPaise: 13050, Rides: 2, Reference: "UTR123",
	})
	svc.Wait()

	m, ok := sender.byToken()["tok-d1"]
	if !ok || len(sender.sent) != 1 {
		t.Fatalf("sent = %+v, want one push to d1", sender.sent)
	}
	if m.Data["type"] != pushTypePayoutSent || m.Data["payoutId"] != "p1" || m.Channel != channelRideRequests {
		t.Errorf("push = %+v", m)
	}
	for _, want := range []string{"₹131", "2 rides", "UTR123"} {
		if !strings.Contains(m.Body, want) {
			t.Errorf("body %q lacks %q", m.Body, want)
		}
	}
}

func TestNotify_AssignedAndCancelledByOps(t *testing.T) {
	svc, tokens, sender, _ := newNotifyTest(t)
	ctx := context.Background()
	_ = tokens.SaveForDriver(ctx, "d1", "tok-d1")
	_ = tokens.SaveForUser(ctx, "u1", "tok-u1")
	start := testNow.Add(3 * time.Hour)
	rb := openRide("r1", start, 2, "automatic")

	ride, plan, _ := toDriverRide(rb, false)
	svc.AssignedByOps(ctx, "d1", ride)
	svc.Wait()
	if m := sender.byToken()["tok-d1"]; m.Data["type"] != pushTypeRideAssigned || m.Data["rideId"] != "r1" ||
		!strings.Contains(m.Body, "India Gate") {
		t.Errorf("assigned push = %+v", m)
	}

	sender.sent = nil
	b := rb.Booking
	b.UserID, b.DriverID, b.CancelReason = "u1", "d1", "Car broke down"
	svc.CancelledByOps(ctx, b, plan)
	svc.Wait()
	got := sender.byToken()
	for _, tok := range []string{"tok-u1", "tok-d1"} {
		m, ok := got[tok]
		if !ok {
			t.Fatalf("no cancel push to %s: %+v", tok, sender.sent)
		}
		if m.Data["type"] != pushTypeRideCancelled || !strings.Contains(m.Body, "MOJUD cancelled") ||
			!strings.Contains(m.Body, "Car broke down") {
			t.Errorf("%s: push = %+v", tok, m)
		}
	}
}
