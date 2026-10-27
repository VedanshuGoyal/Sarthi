// Command server runs the Sarthi REST API: phone-number registration backed by
// PostgreSQL. Real-time GPS/matchmaking (memstore, websockets) is wired
// separately.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sarthi/server/internal/api"
	"github.com/sarthi/server/internal/config"
	"github.com/sarthi/server/internal/kyc/surepass"
	"github.com/sarthi/server/internal/maps/olamaps"
	"github.com/sarthi/server/internal/memstore"
	"github.com/sarthi/server/internal/payment/phonepe"
	"github.com/sarthi/server/internal/push"
	"github.com/sarthi/server/internal/push/fcm"
	"github.com/sarthi/server/internal/repository"
	"github.com/sarthi/server/internal/secret"
	"github.com/sarthi/server/internal/service"
	"github.com/sarthi/server/internal/sms/fast2sms"
	"github.com/sarthi/server/internal/storage"
	"github.com/sarthi/server/pkg/geo"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server exited", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	// Root context cancelled on SIGINT/SIGTERM for graceful shutdown.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := newPool(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	// Sessions: PostgreSQL is the durable source of truth; memstore is the hot
	// cache used to validate tokens without a DB hit. Warm the cache from the DB
	// so tokens issued before this restart keep working.
	sessions := service.NewSessionService(
		repository.NewSessionRepository(pool),
		memstore.NewSessionCache(),
	)
	if n, err := sessions.Warm(ctx); err != nil {
		return err
	} else {
		slog.Info("sessions: warmed cache from DB", "count", n)
	}

	// OTP abuse limits (resend cap, failed-verification cap, 30-min lockout) are
	// Sarthi's own rules, enforced in memory regardless of the SMS provider.
	authOpts := []service.Option{
		service.WithTokenIssuer(sessions),
		service.WithOTPLimiter(memstore.NewOTPGuard()),
	}
	if cfg.Fast2SMS.Enabled() {
		authOpts = append(authOpts, service.WithOTPSender(
			fast2sms.New(cfg.Fast2SMS.APIKey, cfg.Fast2SMS.OTPID),
		))
		slog.Info("otp: Fast2SMS provider enabled")
	} else {
		slog.Warn("otp: no SMS provider configured; accepting dev OTP",
			"devOTP", service.DevOTP)
	}
	authService := service.NewAuthService(repository.NewUserRepository(pool), authOpts...)

	// Driver app auth: same phone/OTP flow, its own account/session tables and
	// OTP-abuse limiter so the two apps' flows never interfere with each other.
	driverSessions := service.NewSessionService(
		repository.NewDriverSessionRepository(pool),
		memstore.NewSessionCache(),
	)
	if n, err := driverSessions.Warm(ctx); err != nil {
		return err
	} else {
		slog.Info("driver sessions: warmed cache from DB", "count", n)
	}
	driverAuthOpts := []service.DriverOption{
		service.WithDriverTokenIssuer(driverSessions),
		service.WithDriverOTPLimiter(memstore.NewOTPGuard()),
	}
	if cfg.Fast2SMS.Enabled() {
		driverAuthOpts = append(driverAuthOpts, service.WithDriverOTPSender(
			fast2sms.New(cfg.Fast2SMS.APIKey, cfg.Fast2SMS.OTPID),
		))
	}
	driverAuthService := service.NewDriverAuthService(repository.NewDriverRepository(pool), driverAuthOpts...)

	// Recent pickups: PostgreSQL is the source of truth; the apps cache their
	// own copy on-device. Low-frequency, so no memstore cache here.
	recentPickups := service.NewRecentPickupService(
		repository.NewRecentPickupRepository(pool),
	)

	// Saved cars: the customer's own cars a driver is hired to drive, picked
	// from a dropdown when booking. PostgreSQL is the source of truth.
	cars := service.NewCarService(repository.NewCarRepository(pool))

	// Who is online right now, bucketed by H3 cell: the driver feed and the
	// "new ride request" pushes both search it.
	presence := memstore.NewDriverTracker(geo.DefaultResolution)
	// Where each driver is while on a ride, for the customer's live map.
	liveLocations := memstore.NewLiveLocations()
	driverProfiles := repository.NewDriverKYCRepository(pool)

	// Push notifications (FCM): "new ride request" to nearby online drivers,
	// ride updates to the customer, "ride cancelled" to the driver.
	pushSender, err := newPushSender(cfg.FCMCredentialsFile, cfg.FCMBaseURL)
	if err != nil {
		return err
	}
	notify := service.NewNotifyService(repository.NewPushTokenRepository(pool), pushSender, presence, driverProfiles)
	defer notify.Wait()

	// Driver KYC: the Document View's images live in object storage, their
	// metadata and the typed fields in PostgreSQL.
	blob, err := newBlobStore(cfg.Storage)
	if err != nil {
		return err
	}
	if cfg.Secrets.Development {
		slog.Warn("kyc: no DOCUMENT_ENCRYPTION_KEY/DOCUMENT_HASH_PEPPER set; " +
			"using fixed development keys — bank details stored now are NOT " +
			"protected, and production must set both")
	}
	documentCipher, err := secret.NewCipher(cfg.Secrets.EncryptionKey)
	if err != nil {
		return err
	}
	// Aadhaar (through DigiLocker), licence and bank account are checked at
	// source by Surepass.
	var verifier service.IdentityVerifier
	if cfg.Surepass.Token != "" {
		verifier = surepass.New(cfg.Surepass.BaseURL, cfg.Surepass.Token)
		slog.Info("kyc: Surepass checks enabled", "digilockerRedirect", cfg.Surepass.DigiLockerRedirectURL)
	} else {
		slog.Warn("kyc: no SUREPASS_TOKEN set; Aadhaar, licence and bank checks are off " +
			"and no driver can finish KYC")
	}
	driverKYC := service.NewDriverKYCService(
		repository.NewDriverKYCRepository(pool),
		blob,
		documentCipher,
		cfg.Secrets.Pepper,
		verifier,
		cfg.Surepass.DigiLockerRedirectURL,
	)

	// Confirmed bookings: persisted to PostgreSQL as the source of truth for
	// what the customer asked for; each one alerts the drivers near it, and
	// the customer can cancel it, rate the driver, see their photo and watch
	// them on the way.
	bookingStore := repository.NewBookingRepository(pool)
	bookings := service.NewBookingService(bookingStore, notify, liveLocations, driverKYC)

	// Driver rides: bookings move through accept → arrive → start → complete
	// in PostgreSQL; who is online right now lives in the in-memory H3 index.
	driverRides := service.NewDriverRideService(
		repository.NewDriverRideRepository(pool),
		driverProfiles,
		presence,
		// Wrong start-code attempts, keyed by ride id (5 per code).
		memstore.NewOTPGuard(),
		liveLocations,
		notify,
	)

	// Ola Maps: the server alone holds the OAuth client secret and hands the
	// apps short-lived tokens (GET /maps/token).
	var mapsTokens service.MapsTokenSource
	if cfg.OlaMaps.Enabled() {
		mapsTokens = olamaps.New(cfg.OlaMaps.ClientID, cfg.OlaMaps.ClientSecret,
			olamaps.WithTokenURL(cfg.OlaMaps.TokenURL))
		slog.Info("maps: Ola Maps token minting enabled")
	} else {
		slog.Warn("maps: no OLA_MAPS_CLIENT_ID/OLA_MAPS_CLIENT_SECRET set; " +
			"GET /maps/token will answer 503 and map search stays off")
	}
	mapsService := service.NewMapsService(mapsTokens)

	// Payments: the customer pays MOJUD for a completed ride by UPI through
	// PhonePe; MOJUD keeps its commission and pays drivers the rest in
	// payouts recorded from the back office.
	paymentStore := repository.NewPaymentRepository(pool)
	var (
		gateway service.PaymentGateway
		webhook api.WebhookVerifier
	)
	if cfg.PhonePe.Enabled() {
		var opts []phonepe.Option
		if cfg.PhonePe.BaseURL != "" {
			opts = append(opts, phonepe.WithURLs(cfg.PhonePe.TokenURL, cfg.PhonePe.BaseURL))
		}
		pp := phonepe.New(phonepe.Config{
			ClientID:        cfg.PhonePe.ClientID,
			ClientSecret:    cfg.PhonePe.ClientSecret,
			ClientVersion:   cfg.PhonePe.ClientVersion,
			MerchantID:      cfg.PhonePe.MerchantID,
			Environment:     phonepe.Environment(cfg.PhonePe.Environment),
			WebhookUsername: cfg.PhonePe.WebhookUsername,
			WebhookPassword: cfg.PhonePe.WebhookPassword,
		}, opts...)
		gateway, webhook = pp, pp
		slog.Info("payments: PhonePe enabled", "environment", cfg.PhonePe.Environment,
			"commissionPercent", float64(cfg.CommissionBasisPoints)/100)
		if cfg.PhonePe.WebhookUsername == "" || cfg.PhonePe.WebhookPassword == "" {
			slog.Warn("payments: no PHONEPE_WEBHOOK_USERNAME/PASSWORD; webhooks are refused " +
				"and payments are confirmed by the app and the 2-minute sweep only")
		}
	} else {
		slog.Warn("payments: no PHONEPE_CLIENT_ID/PHONEPE_CLIENT_SECRET/PHONEPE_MERCHANT_ID set; " +
			"customers can't pay in the app")
	}
	payments := service.NewPaymentService(gateway, paymentStore, bookingStore, notify, cfg.CommissionBasisPoints)
	go payments.RunSweeper(ctx)
	payouts := service.NewPayoutService(paymentStore, documentCipher)
	if cfg.AdminToken == "" {
		slog.Warn("admin: no ADMIN_TOKEN set; GET /users and /admin/* are off")
	}

	srv := &http.Server{
		Addr: cfg.Addr,
		Handler: api.NewRouter(authService, sessions, recentPickups, cars, bookings,
			driverAuthService, driverSessions, driverKYC, driverRides, mapsService, notify,
			payments, payouts, webhook, cfg.AdminToken),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Serve in the background; surface listen errors through a channel.
	serveErr := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serveErr <- err
		}
	}()

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
		slog.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

// newPushSender builds the FCM client from the service-account key at path,
// or returns nil (pushes off) when no path is configured. baseURL, when set,
// replaces Google's endpoint (local testing).
func newPushSender(path, baseURL string) (push.Sender, error) {
	if path == "" {
		slog.Warn("push: no FCM_CREDENTIALS_FILE set; ride notifications are off " +
			"(device tokens are still stored)")
		return nil, nil
	}
	key, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading FCM_CREDENTIALS_FILE: %w", err)
	}
	var opts []fcm.Option
	if baseURL != "" {
		opts = append(opts, fcm.WithBaseURL(baseURL))
	}
	client, err := fcm.New(key, opts...)
	if err != nil {
		return nil, err
	}
	slog.Info("push: FCM enabled", "project", client.ProjectID())
	return client, nil
}

// newBlobStore builds the object store driver KYC images are kept in.
//
// Local disk is the development default so a `go run ./cmd/server` needs no
// cloud account. Production must set STORAGE_BACKEND=s3: images on a VPS's
// filesystem would not survive a rebuild, and re-collecting every driver's
// Aadhaar and licence is not a recoverable position.
func newBlobStore(cfg config.StorageConfig) (storage.Blob, error) {
	switch cfg.Backend {
	case config.StorageS3:
		slog.Info("storage: S3-compatible backend", "bucket", cfg.S3.Bucket, "endpoint", cfg.S3.Endpoint)
		return storage.NewS3(storage.S3Options{
			Bucket:          cfg.S3.Bucket,
			Region:          cfg.S3.Region,
			Endpoint:        cfg.S3.Endpoint,
			AccessKeyID:     cfg.S3.AccessKeyID,
			SecretAccessKey: cfg.S3.SecretAccessKey,
			UsePathStyle:    cfg.S3.UsePathStyle,
		})
	case config.StorageLocal:
		slog.Warn("storage: writing KYC images to local disk; "+
			"set STORAGE_BACKEND=s3 in production", "dir", cfg.LocalDir)
		return storage.NewLocal(cfg.LocalDir)
	default:
		return nil, fmt.Errorf("unknown storage backend %q", cfg.Backend)
	}
}

// newPool opens and verifies a PostgreSQL connection pool.
func newPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	poolCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	poolCfg.MaxConns = 25
	poolCfg.MinConns = 2
	poolCfg.MaxConnLifetime = 5 * time.Minute
	poolCfg.MaxConnIdleTime = time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, err
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}
