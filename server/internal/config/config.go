// Package config loads runtime configuration from the environment.
package config

import (
	"cmp"
	"crypto/sha256"
	"fmt"
	"math"
	"net/url"
	"os"
	"strconv"
	"strings"

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

	// FCMCredentialsFile is the path to the Firebase service-account key
	// (JSON) used to send push notifications. Optional: without it no pushes
	// are sent, though the apps' device tokens are still stored.
	FCMCredentialsFile string

	// FCMBaseURL overrides the FCM endpoint — for local testing against a
	// fake; empty means Google's.
	FCMBaseURL string

	// Secrets holds the keys protecting personal numbers at rest.
	Secrets SecretsConfig

	// PhonePe holds the payment gateway's credentials. Optional: without
	// them customers can't pay in the app (the payment routes answer 503).
	PhonePe PhonePeConfig

	// CommissionBasisPoints is MOJUD's cut of each ride payment, in basis
	// points (1300 = 13%), from COMMISSION_PERCENT; defaultCommissionPercent
	// when unset.
	CommissionBasisPoints int64

	// AllowDevDefaults (ALLOW_DEV_DEFAULTS=1) lets the server boot without an
	// SMS provider (accepting the dev OTP) and without at-rest keys (using the
	// public dev keys). Local runs and CI set it; production must not, so a
	// dropped env var fails the boot instead of silently opening every account.
	AllowDevDefaults bool

	// CORSAllowedOrigins (CORS_ALLOWED_ORIGINS, comma-separated) are browser
	// origins allowed to call the API, besides localhost on any port. The
	// mobile apps and the same-origin admin page need none.
	CORSAllowedOrigins []string

	// AdminToken guards the back-office routes (GET /users, /admin/…).
	// Empty turns them off.
	AdminToken string

	// Surepass checks drivers' Aadhaar (DigiLocker), licence and bank account.
	// Without a token those checks are off and no driver can finish KYC.
	Surepass SurepassConfig

	// Apps is the client compatibility contract: per app, the oldest build
	// the API still serves and the newest one published, and where the APKs
	// are downloaded from (GET /app/config, and 426 below the minimum).
	Apps AppsConfig
}

// DefaultAppDownloadURL is where the APKs are published.
const DefaultAppDownloadURL = "https://apps.mojud.life"

// AppsConfig holds the minimum and latest build of each app. A build is the
// +N of the app's pubspec version.
type AppsConfig struct {
	// DownloadURL (APP_DOWNLOAD_URL) is the page the update screen opens.
	DownloadURL string
	// User is the customer app: MIN_BUILD_USER_APP, LATEST_BUILD_USER_APP.
	User AppBuilds
	// Driver is the driver app: MIN_BUILD_DRIVER_APP, LATEST_BUILD_DRIVER_APP.
	Driver AppBuilds
}

// AppBuilds is one app's build range. Both default to 0; a MinBuild of 0
// blocks nothing, so the gate only observes until a minimum is set.
type AppBuilds struct {
	MinBuild    int
	LatestBuild int
}

// DefaultDigiLockerRedirectURL is the page DigiLocker ends on in production.
const DefaultDigiLockerRedirectURL = "https://api.mojud.life/kyc/digilocker/done"

// SurepassConfig holds the KYC provider's credentials, from Surepass's
// console.
type SurepassConfig struct {
	Token string
	// BaseURL overrides Surepass's production API — for a sandbox or a local
	// fake; empty means production.
	BaseURL string
	// DigiLockerRedirectURL is where DigiLocker sends the driver when done.
	DigiLockerRedirectURL string
}

// PhonePeConfig holds PhonePe payment gateway credentials, from the business
// dashboard's Developer Settings.
type PhonePeConfig struct {
	ClientID      string
	ClientSecret  string
	ClientVersion string
	MerchantID    string
	// Environment is "SANDBOX" (the default) or "PRODUCTION".
	Environment string
	// WebhookUsername / WebhookPassword are what the dashboard's webhook was
	// created with.
	WebhookUsername string
	WebhookPassword string
	// TokenURL / BaseURL override PhonePe's endpoints — for local testing
	// against a fake; empty means PhonePe's own for Environment.
	TokenURL string
	BaseURL  string
}

// Enabled reports whether the credentials needed to take payments are set.
func (c PhonePeConfig) Enabled() bool {
	return c.ClientID != "" && c.ClientSecret != "" && c.MerchantID != ""
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

	allowDev := os.Getenv("ALLOW_DEV_DEFAULTS") == "1"

	storage, err := loadStorage()
	if err != nil {
		return Config{}, err
	}
	secrets, err := loadSecrets(allowDev)
	if err != nil {
		return Config{}, err
	}
	fast2sms := Fast2SMSConfig{
		APIKey: os.Getenv("FAST2SMS_API_KEY"),
		OTPID:  os.Getenv("FAST2SMS_OTP_ID"),
	}
	if !allowDev && !fast2sms.Enabled() {
		return Config{}, fmt.Errorf("FAST2SMS_API_KEY and FAST2SMS_OTP_ID are required; " +
			"without them the fixed dev OTP opens every account (set ALLOW_DEV_DEFAULTS=1 for local runs)")
	}
	adminToken := os.Getenv("ADMIN_TOKEN")
	if !allowDev && adminToken != "" && len(adminToken) < MinAdminTokenLength {
		return Config{}, fmt.Errorf("ADMIN_TOKEN must be at least %d characters "+
			"(generate one with `openssl rand -hex 32`)", MinAdminTokenLength)
	}

	phonePe, err := loadPhonePe()
	if err != nil {
		return Config{}, err
	}
	commission, err := loadCommission()
	if err != nil {
		return Config{}, err
	}
	apps, err := loadApps()
	if err != nil {
		return Config{}, err
	}

	return Config{
		Apps:                  apps,
		PhonePe:               phonePe,
		CommissionBasisPoints: commission,
		AllowDevDefaults:      allowDev,
		CORSAllowedOrigins:    splitList(os.Getenv("CORS_ALLOWED_ORIGINS")),
		AdminToken:            adminToken,
		Surepass: SurepassConfig{
			Token:                 strings.TrimSpace(os.Getenv("SUREPASS_TOKEN")),
			BaseURL:               os.Getenv("SUREPASS_BASE_URL"),
			DigiLockerRedirectURL: cmp.Or(os.Getenv("SUREPASS_DIGILOCKER_REDIRECT_URL"), DefaultDigiLockerRedirectURL),
		},
		DatabaseURL: dsn,
		Addr:        addr,
		Fast2SMS:    fast2sms,
		OlaMaps: OlaMapsConfig{
			ClientID:     os.Getenv("OLA_MAPS_CLIENT_ID"),
			ClientSecret: os.Getenv("OLA_MAPS_CLIENT_SECRET"),
			TokenURL:     os.Getenv("OLA_MAPS_TOKEN_URL"),
		},
		Storage:            storage,
		Secrets:            secrets,
		FCMCredentialsFile: os.Getenv("FCM_CREDENTIALS_FILE"),
		FCMBaseURL:         os.Getenv("FCM_BASE_URL"),
	}, nil
}

// loadPhonePe reads the payment gateway's credentials.
func loadPhonePe() (PhonePeConfig, error) {
	c := PhonePeConfig{
		ClientID:        os.Getenv("PHONEPE_CLIENT_ID"),
		ClientSecret:    os.Getenv("PHONEPE_CLIENT_SECRET"),
		ClientVersion:   os.Getenv("PHONEPE_CLIENT_VERSION"),
		MerchantID:      os.Getenv("PHONEPE_MERCHANT_ID"),
		Environment:     strings.ToUpper(strings.TrimSpace(os.Getenv("PHONEPE_ENV"))),
		WebhookUsername: os.Getenv("PHONEPE_WEBHOOK_USERNAME"),
		WebhookPassword: os.Getenv("PHONEPE_WEBHOOK_PASSWORD"),
		TokenURL:        os.Getenv("PHONEPE_TOKEN_URL"),
		BaseURL:         os.Getenv("PHONEPE_BASE_URL"),
	}
	if (c.TokenURL == "") != (c.BaseURL == "") {
		return PhonePeConfig{}, fmt.Errorf("set both PHONEPE_TOKEN_URL and PHONEPE_BASE_URL, or neither")
	}
	switch c.Environment {
	case "":
		c.Environment = "SANDBOX"
	case "SANDBOX", "PRODUCTION":
	default:
		return PhonePeConfig{}, fmt.Errorf("PHONEPE_ENV must be SANDBOX or PRODUCTION, not %q", c.Environment)
	}
	return c, nil
}

// loadApps reads the client compatibility contract. A typo'd build number
// fails the boot rather than silently turning the gate off.
func loadApps() (AppsConfig, error) {
	c := AppsConfig{
		DownloadURL: cmp.Or(strings.TrimSpace(os.Getenv("APP_DOWNLOAD_URL")), DefaultAppDownloadURL),
	}
	if u, err := url.Parse(c.DownloadURL); err != nil || u.Host == "" ||
		(u.Scheme != "https" && u.Scheme != "http") {
		return AppsConfig{}, fmt.Errorf("APP_DOWNLOAD_URL must be an http(s) URL, not %q", c.DownloadURL)
	}
	for _, f := range []struct {
		env string
		dst *int
	}{
		{"MIN_BUILD_USER_APP", &c.User.MinBuild},
		{"LATEST_BUILD_USER_APP", &c.User.LatestBuild},
		{"MIN_BUILD_DRIVER_APP", &c.Driver.MinBuild},
		{"LATEST_BUILD_DRIVER_APP", &c.Driver.LatestBuild},
	} {
		v := strings.TrimSpace(os.Getenv(f.env))
		if v == "" {
			continue
		}
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 {
			return AppsConfig{}, fmt.Errorf("%s must be a build number (the +N of the app's "+
				"pubspec version), not %q", f.env, v)
		}
		*f.dst = n
	}
	return c, nil
}

// defaultCommissionPercent is MOJUD's commission on each ride payment
// (decided 26 Oct 2026), used when COMMISSION_PERCENT is unset.
const defaultCommissionPercent = "13"

// loadCommission reads COMMISSION_PERCENT ("13", "12.5") as basis points.
func loadCommission() (int64, error) {
	v := strings.TrimSpace(os.Getenv("COMMISSION_PERCENT"))
	if v == "" {
		v = defaultCommissionPercent
	}
	pct, err := strconv.ParseFloat(v, 64)
	if err != nil || pct < 0 || pct > 100 {
		return 0, fmt.Errorf("COMMISSION_PERCENT must be a percentage from 0 to 100, not %q", v)
	}
	return int64(math.Round(pct * 100)), nil
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

// splitList parses a comma-separated env value, dropping blanks.
func splitList(v string) []string {
	var out []string
	for _, part := range strings.Split(v, ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

// MinAdminTokenLength is the shortest ADMIN_TOKEN accepted outside dev mode.
// The token alone guards decrypted bank numbers and KYC decisions.
const MinAdminTokenLength = 32

// loadSecrets reads the at-rest protection keys.
//
// They come as a pair: setting only one is always an error, because the
// other would silently fall back to a public constant. With neither set,
// allowDev (ALLOW_DEV_DEFAULTS=1) derives both from a fixed public constant so
// local runs and CI work out of the box, and main logs a warning; without it
// the boot fails. The constant is deliberately stable rather than random — a
// key regenerated on every boot would silently orphan anything encrypted
// before the restart.
func loadSecrets(allowDev bool) (SecretsConfig, error) {
	encoded := os.Getenv("DOCUMENT_ENCRYPTION_KEY")
	pepper := os.Getenv("DOCUMENT_HASH_PEPPER")

	if (encoded == "") != (pepper == "") {
		return SecretsConfig{}, fmt.Errorf("set both DOCUMENT_ENCRYPTION_KEY and DOCUMENT_HASH_PEPPER, or neither")
	}
	if encoded == "" {
		if !allowDev {
			return SecretsConfig{}, fmt.Errorf("DOCUMENT_ENCRYPTION_KEY and DOCUMENT_HASH_PEPPER are required; " +
				"without them bank numbers are sealed with a public key (set ALLOW_DEV_DEFAULTS=1 for local runs)")
		}
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

// DevEncryptionKey is the public key used when ALLOW_DEV_DEFAULTS=1 and no
// DOCUMENT_ENCRYPTION_KEY is set. cmd/rekey uses it to move data sealed under
// it to a real key.
func DevEncryptionKey() []byte { return devSecret("encryption-key") }

// devSecret derives a fixed, deliberately public development key from label.
func devSecret(label string) []byte {
	sum := sha256.Sum256([]byte("sarthi-development-" + label))
	return sum[:]
}
