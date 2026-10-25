// Package push describes a phone notification independently of the service
// that delivers it (Firebase Cloud Messaging today, see push/fcm).
package push

import (
	"context"
	"errors"
	"time"
)

// ErrUnregistered is returned when a device token is no longer valid — the
// app was uninstalled or signed out — so the caller should forget it.
var ErrUnregistered = errors.New("push token is no longer registered")

// Message is one notification for one app install.
type Message struct {
	// Token is the install's registration token.
	Token string
	Title string
	Body  string
	// Channel is the Android notification channel id the app created; it
	// decides the sound and whether the notification pops up.
	Channel string
	// Tag replaces an earlier notification with the same tag rather than
	// stacking a second one (e.g. one per ride).
	Tag string
	// Data reaches the app alongside the notification, for routing a tap.
	Data map[string]string
	// TTL is how long delivery is worth trying while the phone is offline;
	// zero leaves it to the provider (four weeks for FCM).
	TTL time.Duration
}

// Sender delivers a message to a device.
type Sender interface {
	Send(ctx context.Context, m Message) error
}
