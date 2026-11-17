package service

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/push"
)

// Pushes for money and the back office (money+ops). Kept beside, not in,
// notify_service.go; same channels and conventions.
const (
	pushTypePayoutSent   = "payout_sent"
	pushTypeRideAssigned = "ride_assigned"
)

// PayoutSent tells a driver that MOJUD recorded transfer p to their bank,
// with the reference to look for on their statement.
func (s *NotifyService) PayoutSent(ctx context.Context, p domain.DriverPayout) {
	rides := "rides"
	if p.Rides == 1 {
		rides = "ride"
	}
	body := fmt.Sprintf("%s for %d %s is on its way to your bank. Reference: %s",
		formatFare(p.AmountPaise, false), p.Rides, rides, p.Reference)
	s.background(ctx, func(ctx context.Context) {
		s.sendToDriver(ctx, p.DriverID, push.Message{
			Title: "Payout sent",
			Body:  body,
			Tag:   "payout-" + p.ID,
			Data:  map[string]string{"type": pushTypePayoutSent, "payoutId": p.ID},
			TTL:   7 * 24 * time.Hour,
		})
	})
}

// AssignedByOps tells driverID that MOJUD gave them ride — an ops assign,
// rather than one they accepted themselves.
func (s *NotifyService) AssignedByOps(ctx context.Context, driverID string, ride domain.DriverRide) {
	body := fmt.Sprintf("MOJUD gave you a ride on %s from %s. Open the app for the details.",
		formatWhen(ride.ScheduledAt), ride.Pickup.Address)
	s.background(ctx, func(ctx context.Context) {
		s.sendToDriver(ctx, driverID, push.Message{
			Title: "Ride assigned to you",
			Body:  body,
			Tag:   "ride-" + ride.ID,
			Data:  map[string]string{"type": pushTypeRideAssigned, "rideId": ride.ID},
			TTL:   max(ride.ScheduledAt.Sub(s.now()), 10*time.Minute),
		})
	})
}

// CancelledByOps tells the customer of booking b, and the driver who had
// it, that MOJUD cancelled it — and why, when the operator said.
func (s *NotifyService) CancelledByOps(ctx context.Context, b domain.Booking, plan tripPlan) {
	when := formatWhen(plan.ScheduledAt)
	reason := ""
	if b.CancelReason != "" {
		reason = "\nReason: " + b.CancelReason
	}
	ttl := max(plan.ScheduledAt.Sub(s.now()), 10*time.Minute)
	s.background(ctx, func(ctx context.Context) {
		s.tellCustomer(ctx, b.UserID, b.ID, pushTypeRideCancelled, "Ride cancelled",
			fmt.Sprintf("MOJUD cancelled your ride on %s.%s", when, reason), ttl)
		if b.DriverID != "" {
			s.sendToDriver(ctx, b.DriverID, push.Message{
				Title: "Ride cancelled",
				Body:  fmt.Sprintf("MOJUD cancelled the ride on %s (%s).%s", when, tripLabel(b.TripType, plan), reason),
				Tag:   "ride-" + b.ID,
				Data:  map[string]string{"type": pushTypeRideCancelled, "rideId": b.ID},
				TTL:   ttl,
			})
		}
	})
}

// sendToDriver sends m, on the driver channel, to every install of driverID.
// Call it from background.
func (s *NotifyService) sendToDriver(ctx context.Context, driverID string, m push.Message) {
	byDriver, err := s.tokens.ForDrivers(ctx, []string{driverID})
	if err != nil {
		slog.WarnContext(ctx, "push: loading driver tokens failed", "driverId", driverID, "error", err)
		return
	}
	m.Channel = channelRideRequests
	sent := 0
	for _, token := range byDriver[driverID] {
		m.Token = token
		if s.send(ctx, m) {
			sent++
		}
	}
	slog.InfoContext(ctx, "push: driver update sent", "type", m.Data["type"], "driverId", driverID, "devices", sent)
}
