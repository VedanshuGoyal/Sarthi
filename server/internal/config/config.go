// Package config loads runtime configuration from the environment.
package config

import (
	"crypto/sha256"
	"fmt"
	"os"

	"github.com/sarthi/server/internal/secret"
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

	// OlaMaps holds the Ola Maps OAuth client credentials. Optional: without
	// them GET /maps/token answers 503 and the apps show "maps isn't set up".
	OlaMaps OlaMapsConfig

	// Storage says where driver KYC images are kept.
	Storage StorageConfig

	// Secrets holds the keys protecting personal numbers at rest.
	Secrets SecretsConfig
}

// StorageBackend names an object-storage implementation.
type StorageBackend string

const (
	// StorageLocal writes objects to a directory on this machine. Development
	// only — a VPS rebuild would take every driver's KYC with it.
	StorageLocal StorageBackend = "local"
	// StorageS3 writes to any S3-compatible service (Cloudflare R2, AWS S3,
	// Backblaze B2, MinIO). The production choice.
	StorageS3 StorageBackend = "s3"
)

// StorageConfig selects and configures the object store.
type StorageConfig struct {
	Backend StorageBackend
	// LocalDir is the root directory for [StorageLocal].
	LocalDir string
	// S3 is read only when Backend is [StorageS3].
	S3 S3Config
}

// S3Config holds credentials and addressing for an S3-compatible service.
type S3Config struct {
	Bucket string
	// Region is "auto" on R2, a real region on AWS.
	Region string
	// Endpoint is the service URL; empty means AWS S3 itself.
	Endpoint        string
	AccessKeyID     string
	SecretAccessKey string
	// UsePathStyle addresses buckets as <endpoint>/<bucket>/<key>. MinIO needs
	// it; R2 and AWS do not.
	UsePathStyle bool
}

// SecretsConfig carries the keys used to protect personal numbers at rest:
// EncryptionKey seals bank account numbers, Pepper fingerprints Aadhaar
// numbers. See the secret package for why the two are treated differently.
type SecretsConfig struct {
	EncryptionKey []byte
	Pepper        []byte
	// Development reports that the environment supplied neither, so both were
	// derived from a fixed public constant. Never true in production.
	Development bool
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

// OlaMapsConfig holds the Ola Maps OAuth 2.0 client credentials. They stay on
// the server: the apps never see the secret, only the short-lived bearer tokens
// minted with it (GET /maps/token).
type OlaMapsConfig struct {
	ClientID     string
	ClientSecret string
	// TokenURL overrides Ola's token endpoint; empty means the default.
	TokenURL string
}

// Enabled reports whether both credentials are present.
func (c OlaMapsConfig) Enabled() bool {
	return c.ClientID != "" && c.ClientSecret != ""
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

	storage, err := loadStorage()
	if err != nil {
		return Config{}, err
	}
	secrets, err := loadSecrets()
	if err != nil {
		return Config{}, err
	}

	return Config{
		DatabaseURL: dsn,
		Addr:        addr,
		Fast2SMS: Fast2SMSConfig{
			APIKey: os.Getenv("FAST2SMS_API_KEY"),
			OTPID:  os.Getenv("FAST2SMS_OTP_ID"),
		},
		OlaMaps: OlaMapsConfig{
			ClientID:     os.Getenv("OLA_MAPS_CLIENT_ID"),
			ClientSecret: os.Getenv("OLA_MAPS_CLIENT_SECRET"),
			TokenURL:     os.Getenv("OLA_MAPS_TOKEN_URL"),
		},
		Storage: storage,
		Secrets: secrets,
	}, nil
}

// loadStorage reads the object-storage settings, defaulting to a local
// directory so a `go run ./cmd/server` needs no cloud account.
func loadStorage() (StorageConfig, error) {
	backend := StorageBackend(os.Getenv("STORAGE_BACKEND"))
	if backend == "" {
		backend = StorageLocal
	}

	switch backend {
	case StorageLocal:
		dir := os.Getenv("STORAGE_LOCAL_DIR")
		if dir == "" {
			dir = ".data/uploads"
		}
		return StorageConfig{Backend: backend, LocalDir: dir}, nil

	case StorageS3:
		s3 := S3Config{
			Bucket:          os.Getenv("S3_BUCKET"),
			Region:          os.Getenv("S3_REGION"),
			Endpoint:        os.Getenv("S3_ENDPOINT"),
			AccessKeyID:     os.Getenv("S3_ACCESS_KEY_ID"),
			SecretAccessKey: os.Getenv("S3_SECRET_ACCESS_KEY"),
			UsePathStyle:    os.Getenv("S3_USE_PATH_STYLE") == "true",
		}
		// Fail at boot rather than on the first driver's upload.
		if s3.Bucket == "" {
			return StorageConfig{}, fmt.Errorf("S3_BUCKET is required when STORAGE_BACKEND=s3")
		}
		if s3.AccessKeyID == "" || s3.SecretAccessKey == "" {
			return StorageConfig{}, fmt.Errorf("S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY are required when STORAGE_BACKEND=s3")
		}
		return StorageConfig{Backend: backend, S3: s3}, nil

	default:
		return StorageConfig{}, fmt.Errorf("unknown STORAGE_BACKEND %q (want %q or %q)", backend, StorageLocal, StorageS3)
	}
}

// loadSecrets reads the at-rest protection keys.
//
// Both are optional, mirroring how a missing SMS provider falls back to the
// dev OTP: an unconfigured environment derives them from a fixed public
// constant so local runs and CI work out of the box, and main logs a warning.
// The constant is deliberately stable rather than random — a key regenerated
// on every boot would silently orphan anything encrypted before the restart.
func loadSecrets() (SecretsConfig, error) {
	encoded := os.Getenv("DOCUMENT_ENCRYPTION_KEY")
	pepper := os.Getenv("DOCUMENT_HASH_PEPPER")

	if encoded == "" || pepper == "" {
		return SecretsConfig{
			EncryptionKey: devSecret("encryption-key"),
			Pepper:        devSecret("hash-pepper"),
			Development:   true,
		}, nil
	}

	key, err := secret.ParseKey(encoded)
	if err != nil {
		return SecretsConfig{}, fmt.Errorf("DOCUMENT_ENCRYPTION_KEY: %w (generate one with `openssl rand -base64 32`)", err)
	}
	return SecretsConfig{EncryptionKey: key, Pepper: []byte(pepper)}, nil
}

// devSecret derives a fixed, deliberately public development key from label.
func devSecret(label string) []byte {
	sum := sha256.Sum256([]byte("sarthi-development-" + label))
	return sum[:]
}
