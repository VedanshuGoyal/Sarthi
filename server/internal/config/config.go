// Package config loads runtime configuration from the environment.
package config

import (
	"fmt"
	"os"
)

// Config holds everything the server needs to boot.
type Config struct {
	// DatabaseURL is the PostgreSQL connection string (pgx/libpq DSN), e.g.
	// postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable
	DatabaseURL string

	// Addr is the TCP address the HTTP server listens on (e.g. ":8080").
	Addr string

	// Fast2SMS configures the SMS OTP provider. Both fields are optional: when
	// either is empty the server falls back to the fixed dev OTP so local runs
	// and CI don't need real credentials.
	Fast2SMS Fast2SMSConfig
}

// Fast2SMSConfig holds credentials for the Fast2SMS managed-OTP API
// (https://docs.fast2sms.com/reference/send-otp).
type Fast2SMSConfig struct {
	// APIKey authenticates requests (sent as the Authorization header).
	APIKey string
	// OTPID is the pre-registered OTP template identifier used when sending.
	OTPID string
}

// Enabled reports whether both credentials are present, i.e. a real SMS
// provider should be wired up instead of the dev OTP.
func (c Fast2SMSConfig) Enabled() bool {
	return c.APIKey != "" && c.OTPID != ""
}

// Load reads configuration from the environment. DATABASE_URL is required so we
// fail fast rather than starting a server that can't persist anything.
func Load() (Config, error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		return Config{}, fmt.Errorf("DATABASE_URL is required")
	}

	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = ":8080"
	}

	return Config{
		DatabaseURL: dsn,
		Addr:        addr,
		Fast2SMS: Fast2SMSConfig{
			APIKey: os.Getenv("FAST2SMS_API_KEY"),
			OTPID:  os.Getenv("FAST2SMS_OTP_ID"),
		},
	}, nil
}
