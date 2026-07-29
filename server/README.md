# Sarthi backend

Go REST API for phone-number registration, backed by PostgreSQL (the source of
truth for accounts). Real-time GPS/matchmaking lives in `internal/memstore`.

## Run it

```bash
# 1. Start Postgres (creates the `users` table on first boot).
docker compose up -d

# 2. Point the server at it and run.
export DATABASE_URL='postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable'
go run ./cmd/server
# → listening on :8080
```

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

Two supported paths — pick one, they compete for ports :80, :443 and :5432:

| Path | Use when |
| ---- | -------- |
| **[Native (scripted)](deploy/README.md)** — `sudo deploy/setup-vps.sh` | You want direct `psql`/`journalctl` access, or the box is small (≤1 GB RAM). One idempotent script does everything below automatically. |
| **Docker Compose** (this section) | You want the runtime pinned in an image and the host left untouched. |

### Docker Compose

One-time setup on a fresh Ubuntu VPS (Hetzner/DigitalOcean/etc.):

```bash
# On the VPS: install Docker.
curl -fsSL https://get.docker.com | sh

# Point DNS: create an A record for your domain -> the VPS's IP, then confirm
# it resolves before starting Caddy (it needs this to issue a TLS cert):
dig +short api.yourdomain.com
```

Ship the code and bring the stack up:

```bash
# From your machine: copy the server/ dir to the VPS (or just `git clone` the
# repo there and cd into server/).
rsync -av --exclude .git ./server/ user@your-vps:/opt/sarthi/server/

# On the VPS, in /opt/sarthi/server:
cp .env.prod.example .env.prod   # fill in DOMAIN, POSTGRES_PASSWORD, FAST2SMS_*
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build

# Apply migrations against the running db container:
docker compose -f docker-compose.prod.yml --env-file .env.prod exec db \
  psql -U sarthi -d sarthi -f - < migrations/0001_create_users.up.sql
# repeat per migration file, in order (or install golang-migrate on the VPS
# and point it at postgres://sarthi:$POSTGRES_PASSWORD@localhost:5432/sarthi).
```

Caddy handles TLS issuance/renewal and reverse-proxies both REST and WebSocket
traffic to the `server` container — see `Caddyfile`. To ship a new version
later: `git pull && docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build`.

Before opening this up beyond your own testing: put `/users` behind auth (see
note above), and add a periodic sweep for expired sessions.
```
