# Sarthi backend

Go REST API for phone-number registration, backed by PostgreSQL (the source of
truth for accounts). Real-time GPS/matchmaking lives in `internal/memstore`.

## Run it (local development)

Local development uses Docker for Postgres only — the Go server runs on the
host. (Production is different: the VPS runs everything natively, no Docker —
see [Deploying to a VPS](#deploying-to-a-vps).)

The one-liner, which starts Postgres, waits for it, applies every migration and
then runs the server:

```bash
./scripts/run-backend.sh
# → listening on :8080
```

Or by hand:

```bash
# 1. Start Postgres (creates the full schema on first boot).
docker compose up -d

# 2. Point the server at it and run.
export DATABASE_URL='postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable'
go run ./cmd/server
# → listening on :8080
```

On macOS the Docker daemon comes from Colima — see [SETUP.md](../SETUP.md).

The compose file seeds the schema via Postgres' init hook, which only fires on
an **empty** data volume. If you already have a DB and a new migration lands,
use `./scripts/run-backend.sh` (it replays all of them, idempotently) or apply
it by hand as below.

### SMS OTP (Fast2SMS)

OTP delivery uses the [Fast2SMS managed-OTP API](https://docs.fast2sms.com/reference/send-otp):
Fast2SMS generates, texts, and verifies the code, so the backend stores no OTP
state. Set both variables to enable it:

```bash
export FAST2SMS_API_KEY='your-fast2sms-api-key'   # dashboard → Dev API → API Key
export FAST2SMS_OTP_ID='your-otp-template-id'      # a registered OTP template
```

Leave them unset for local dev/CI: the server logs a warning and accepts the
fixed dev code `123456`.

If you already have Postgres, apply the migration manually instead of step 1:

```bash
psql "$DATABASE_URL" -f migrations/0001_create_users.up.sql
psql "$DATABASE_URL" -f migrations/0002_create_sessions.up.sql
# or, with golang-migrate:
migrate -path migrations -database "$DATABASE_URL" up
```

## Endpoints

| Method | Path                | Body                                              | Notes |
| ------ | ------------------- | ------------------------------------------------- | ----- |
| POST   | `/auth/otp`         | `{ "phoneE164": "+919876543210" }`                | Sends OTP via Fast2SMS (dev code `123456` when no provider is configured) |
| POST   | `/auth/otp/resend`  | `{ "phoneE164": "+919876543210" }`                | Re-sends the last OTP (provider enforces window/attempt limits) |
| POST   | `/auth/otp/verify`  | `{ "phoneE164": "...", "code": "123456" }`        | Login-or-register. 401 on wrong code. Existing number → `{registered:true, token, user}` (logged in); new number → `{registered:false}` (collect a profile, then register) |
| POST   | `/auth/register`    | `{ "phoneE164", "name", "email", "dateOfBirth" }` | `dateOfBirth` is `YYYY-MM-DD`; 201 → `{registered:true, token, user}`, 409 if phone taken |
| GET    | `/auth/me`          | — (Bearer token)                                  | The authenticated user's account. 401 without a valid token |
| POST   | `/auth/logout`      | — (Bearer token)                                  | Revokes the caller's session token |
| GET    | `/users`            | —                                                 | All accounts, newest first (diagnostic — unauthenticated) |
| GET    | `/healthz`          | —                                                 | Liveness |

Authenticated endpoints expect the session token as `Authorization: Bearer <token>`.

## Check all registered accounts

Once the server is running and you've registered from the app:

```bash
# Via the API:
curl -s localhost:8080/users | jq

# Or straight from the database:
psql "$DATABASE_URL" -c \
  "SELECT id, phone_e164, name, email, date_of_birth, created_at FROM users ORDER BY created_at DESC;"
```

## Smoke test without the app

```bash
curl -s -XPOST localhost:8080/auth/otp -d '{"phoneE164":"+919876543210"}'
curl -s -XPOST localhost:8080/auth/otp/verify -d '{"phoneE164":"+919876543210","code":"123456"}'
curl -s -XPOST localhost:8080/auth/register \
  -d '{"phoneE164":"+919876543210","name":"Asha Sharma","email":"asha@example.com","dateOfBirth":"2000-01-01"}' | jq
curl -s localhost:8080/users | jq
```

## Notes

- OTP delivery goes through Fast2SMS when `FAST2SMS_API_KEY`/`FAST2SMS_OTP_ID`
  are set; otherwise a fixed dev code (`123456`) is accepted. The provider is an
  outbound adapter in `internal/sms/fast2sms`, wired via `service.WithOTPSender`.
- Auth uses opaque bearer tokens. On login/registration the server mints a
  session, writes it to PostgreSQL (durable source of truth) **and** an in-memory
  `memstore.SessionCache` (the hot path — `/auth/me` etc. validate from memory,
  no DB hit). On boot the cache is warmed from the DB so tokens survive a
  restart. Sessions expire after `service.DefaultSessionTTL` (30 days); expired
  rows are not yet swept (add a periodic job before production).
- `/users` is intentionally open for development. Put it behind admin auth before
  shipping.
- Migrations are versioned in `migrations/` and should be reviewed by a human
  before production (column types, indexing, constraints).

## Deploying to a VPS

**No Docker in production.** The VPS runs Go, PostgreSQL 17 and Caddy directly
under systemd; Docker is a local-development convenience only. Everything is
scripted and idempotent:

```bash
# On a fresh Ubuntu 24.04 box, with a DNS A record already pointing at it:
git clone git@github.com:VedanshuGoyal/Sarthi.git
cd Sarthi/server
cp .env.prod.example .env.prod   # fill in DOMAIN, POSTGRES_PASSWORD, FAST2SMS_*
sudo deploy/setup-vps.sh
```

That provisions Go, Postgres, the database, migrations, the `sarthi` systemd
unit, Caddy (Let's Encrypt TLS, REST + WebSocket), and the firewall — then
health-checks the result and prints your `API_BASE_URL`.

To ship a new version afterwards:

```bash
sudo deploy/redeploy.sh --pull   # builds, swaps, health-checks, auto-rollback
```

Re-running `setup-vps.sh` is the intended way to apply a config change, and
individual phases can be run by name (`sudo deploy/setup-vps.sh migrations`).

Full runbook, operational commands and gotchas: **[deploy/README.md](deploy/README.md)**.

Before opening this up beyond your own testing: put `/users` behind auth (see
note above), and add a periodic sweep for expired sessions.
