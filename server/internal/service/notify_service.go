package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/sarthi/server/internal/domain"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/internal/push"
)

// ErrInvalidPushToken is returned when an app registers an empty or
// implausibly long device token.
var ErrInvalidPushToken = errors.New("push token is required")

// Android notification channels. The apps create them at start-up with the
// same ids; the channel decides the sound and that the alert pops up.
const (
	channelRideRequests = "ride_requests" // driver app
	channelRideUpdates  = "ride_updates"  // customer app
)

// Notification types, sent in the data payload so a tap opens the right tab.
const (
	pushTypeRideRequest    = "ride_request"
	pushTypeDriverAssigned = "driver_assigned"
)

const (
	// presenceFresh is how recently an online driver's app must have
	// reported in to be alerted. The driver app re-reports every 20 s while
	// on duty, so a stale entry means the app was closed without going
	// offline.
	presenceFresh = 10 * time.Minute

	// maxAlertedDrivers caps one request's fan-out, nearest first.
	maxAlertedDrivers = 200

	// pushTimeout bounds one event's sends.
	pushTimeout = 30 * time.Second

	maxPushTokenLen = 4096
)

// PushTokenStore persists app installs' push tokens
// (repository.PushTokenRepository).
type PushTokenStore interface {
	SaveForUser(ctx context.Context, userID, token string) error
	SaveForDriver(ctx context.Context, driverID, token string) error
	DeleteForUser(ctx context.Context, userID, token string) error
	DeleteForDriver(ctx context.Context, driverID, token string) error
	Delete(ctx context.Context, token string) error
	ForUser(ctx context.Context, userID string) ([]string, error)
	ForDrivers(ctx context.Context, driverIDs []string) (map[string][]string, error)
}

// NearbyDriverFinder searches the live presence index
// (memstore.DriverTracker).
type NearbyDriverFinder interface {
	FindNearbyDrivers(lat, lng, radiusMeters float64, limit int) ([]memstore.NearbyDriver, error)
}

// NotifyService sends the apps' push notifications, Uber-style:
//
//   - a customer books → every online driver within requestRadiusM of the
//     pickup who could take it gets "New ride request";
//   - a driver accepts → the customer gets "Driver assigned".
//
// Sends run in the background so a slow push never delays the booking or
// accept response. Without a sender (no FCM credentials) nothing is sent,
// but device tokens are still collected for when one is configured.
type NotifyService struct {
	tokens   PushTokenStore
	sender   push.Sender
	drivers  NearbyDriverFinder
	profiles DriverProfileReader
	now      func() time.Time
	wg       sync.WaitGroup
}

// NewNotifyService wires the service. sender may be nil (pushes off).
func NewNotifyService(tokens PushTokenStore, sender push.Sender, drivers NearbyDriverFinder, profiles DriverProfileReader) *NotifyService {
	return &NotifyService{
		tokens:   tokens,
		sender:   sender,
		drivers:  drivers,
		profiles: profiles,
		now:      time.Now,
	}
}

// RegisterUserDevice records token as userID's customer-app install.
func (s *NotifyService) RegisterUserDevice(ctx context.Context, userID, token string) error {
	token, err := cleanPushToken(token)
	if err != nil {
		return err
	}
	return s.tokens.SaveForUser(ctx, userID, token)
}

// ForgetUserDevice drops userID's install token (sign-out).
func (s *NotifyService) ForgetUserDevice(ctx context.Context, userID, token string) error {
	token, err := cleanPushToken(token)
	if err != nil {
		return err
	}
	return s.tokens.DeleteForUser(ctx, userID, token)
}

// RegisterDriverDevice records token as driverID's driver-app install.
func (s *NotifyService) RegisterDriverDevice(ctx context.Context, driverID, token string) error {
	token, err := cleanPushToken(token)
	if err != nil {
		return err
	}
	return s.tokens.SaveForDriver(ctx, driverID, token)
}

// ForgetDriverDevice drops driverID's install token (sign-out).
func (s *NotifyService) ForgetDriverDevice(ctx context.Context, driverID, token string) error {
	token, err := cleanPushToken(token)
	if err != nil {
		return err
	}
	return s.tokens.DeleteForDriver(ctx, driverID, token)
}

// RideRequested alerts the drivers who could take booking b: online, near
// its pickup, KYC-cleared and driving its gearbox. Each sees how far away
// the pickup is.
func (s *NotifyService) RideRequested(ctx context.Context, b domain.Booking, plan tripPlan) {
	s.background(ctx, func(ctx context.Context) {
		closesIn := plan.ScheduledAt.Add(-acceptCutoff).Sub(s.now())
		if closesIn <= 0 {
			return
		}
		nearby, err := s.drivers.FindNearbyDrivers(plan.Pickup.Lat, plan.Pickup.Lng, requestRadiusM, maxAlertedDrivers)
		if err != nil {
			slog.WarnContext(ctx, "push: finding drivers for request failed", "rideId", b.ID, "error", err)
			return
		}
		distance := map[string]float64{}
		var ids []string
		for _, n := range nearby {
			if s.now().Sub(n.Driver.Location.UpdatedAt) > presenceFresh {
				continue
			}
			p, err := s.profiles.FindProfile(ctx, n.Driver.ID)
			if err != nil || (p.KYCStatus != domain.KYCSubmitted && p.KYCStatus != domain.KYCVerified) ||
				!canDrive(p.Transmission, plan.Car) {
				continue
			}
			ids = append(ids, n.Driver.ID)
			distance[n.Driver.ID] = n.DistanceM
		}
		if len(ids) == 0 {
			slog.InfoContext(ctx, "push: no online drivers near request", "rideId", b.ID)
			return
		}
		byDriver, err := s.tokens.ForDrivers(ctx, ids)
		if err != nil {
			slog.WarnContext(ctx, "push: loading driver tokens failed", "rideId", b.ID, "error", err)
			return
		}

		fare, estimated := b.FarePaise, b.FareEstimated
		if fare == 0 {
			fare, estimated = plan.Fare()
		}
		title := "New ride request · " + formatFare(fare, estimated)
		sent := 0
		for driverID, tokens := range byDriver {
			body := fmt.Sprintf("%s · %s · %s away", formatWhen(plan.ScheduledAt), tripLabel(b.TripType, plan),
				formatDistance(distance[driverID]))
			if plan.Pickup.Address != "" {
				body += "\nPickup: " + plan.Pickup.Address
			}
			for _, token := range tokens {
				if s.send(ctx, push.Message{
					Token:   token,
					Title:   title,
					Body:    body,
					Channel: channelRideRequests,
					Tag:     "ride-" + b.ID,
					Data:    map[string]string{"type": pushTypeRideRequest, "rideId": b.ID},
					TTL:     closesIn,
				}) {
					sent++
				}
			}
		}
		slog.InfoContext(ctx, "push: ride request sent", "rideId", b.ID, "drivers", len(byDriver), "devices", sent)
	})
}

// DriverAssigned tells customer userID that driverName took their ride.
func (s *NotifyService) DriverAssigned(ctx context.Context, userID string, ride domain.DriverRide, driverName string) {
	s.background(ctx, func(ctx context.Context) {
		tokens, err := s.tokens.ForUser(ctx, userID)
		if err != nil {
			slog.WarnContext(ctx, "push: loading customer tokens failed", "rideId", ride.ID, "error", err)
			return
		}
		name := strings.TrimSpace(driverName)
		if name == "" {
			name = "A driver"
		}
		body := fmt.Sprintf("%s is your driver for %s.", name, formatWhen(ride.ScheduledAt))
		if ride.Pickup.Address != "" {
			body += "\nPickup: " + ride.Pickup.Address
		}
		ttl := max(ride.ScheduledAt.Sub(s.now()), 10*time.Minute)
		sent := 0
		for _, token := range tokens {
			if s.send(ctx, push.Message{
				Token:   token,
				Title:   "Driver assigned",
				Body:    body,
				Channel: channelRideUpdates,
				Tag:     "ride-" + ride.ID,
				Data:    map[string]string{"type": pushTypeDriverAssigned, "rideId": ride.ID},
				TTL:     ttl,
			}) {
				sent++
			}
		}
		slog.InfoContext(ctx, "push: driver assigned sent", "rideId", ride.ID, "devices", sent)
	})
}

// Wait blocks until in-flight sends finish (graceful shutdown).
func (s *NotifyService) Wait() { s.wg.Wait() }

// background runs fn off the request path with its own deadline, detached
// from the request's cancellation. No-op when pushes are off.
func (s *NotifyService) background(ctx context.Context, fn func(context.Context)) {
	if s.sender == nil {
		return
	}
	ctx = context.WithoutCancel(ctx)
	s.wg.Add(1)
	go func() {
		defer s.wg.Done()
		ctx, cancel := context.WithTimeout(ctx, pushTimeout)
		defer cancel()
		fn(ctx)
	}()
}

// send delivers m, forgetting its token if FCM says the install is gone.
func (s *NotifyService) send(ctx context.Context, m push.Message) bool {
	err := s.sender.Send(ctx, m)
	if errors.Is(err, push.ErrUnregistered) {
		if err := s.tokens.Delete(ctx, m.Token); err != nil {
			slog.WarnContext(ctx, "push: dropping dead token failed", "error", err)
		}
		return false
	}
	if err != nil {
		slog.WarnContext(ctx, "push: send failed", "channel", m.Channel, "error", err)
		return false
	}
	return true
}

func cleanPushToken(token string) (string, error) {
	token = strings.TrimSpace(token)
	if token == "" || len(token) > maxPushTokenLen {
		return "", ErrInvalidPushToken
	}
	return token, nil
}

// tripLabel names the trip the way the apps do.
func tripLabel(tripType string, plan tripPlan) string {
	switch tripType {
	case TripRoundTrip:
		if plan.Hours > 0 {
			return fmt.Sprintf("Round trip, %d h", plan.Hours)
		}
		return "Round trip"
	case TripOneWay:
		return "One way"
	case TripMultiStop:
		if n := len(plan.Stops); n == 1 {
			return "Multi-stop, 1 stop"
		} else if n > 1 {
			return fmt.Sprintf("Multi-stop, %d stops", n)
		}
		return "Multi-stop"
	default:
		return "Ride"
	}
}

// formatWhen renders a start time in IST, e.g. "Mon 26 Oct, 10:30 AM".
func formatWhen(t time.Time) string {
	return t.In(ist).Format("Mon 2 Jan, 3:04 PM")
}

// formatDistance renders metres as "800 m" or "3.2 km".
func formatDistance(m float64) string {
	if m < 1000 {
		return fmt.Sprintf("%d m", int(m/100+0.5)*100)
	}
	return strconv.FormatFloat(m/1000, 'f', 1, 64) + " km"
}

// formatFare renders paise as whole rupees with Indian digit grouping, e.g.
// "₹1,23,400", prefixed "~" when estimated.
func formatFare(paise int64, estimated bool) string {
	digits := strconv.FormatInt((paise+50)/100, 10)
	if len(digits) > 3 {
		head, tail := digits[:len(digits)-3], digits[len(digits)-3:]
		var groups []string
		for len(head) > 2 {
			groups = append([]string{head[len(head)-2:]}, groups...)
			head = head[:len(head)-2]
		}
		groups = append([]string{head}, groups...)
		digits = strings.Join(groups, ",") + "," + tail
	}
	if estimated {
		return "~₹" + digits
	}
	return "₹" + digits
}
