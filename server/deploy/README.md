# Native VPS deployment

Scripted setup for running the backend **directly on an Ubuntu 24.04 VPS** —
no Docker. This is an alternative to the Compose stack in
`../docker-compose.prod.yml`; pick one, not both (they compete for :80, :443
and :5432).

```
Internet ──▶ Caddy :80/:443 ──▶ sarthi-server :8080 ──▶ PostgreSQL 17 :5432
             (Let's Encrypt)     (systemd, user `sarthi`)  (localhost only)
```

## Why choose this over Docker

|                    | Native (this dir)                            | Docker (`../docker-compose.prod.yml`)  |
| ------------------ | -------------------------------------------- | -------------------------------------- |
| Inspecting the DB  | `sudo -u postgres psql sarthi`                | `docker compose exec db psql ...`      |
| Logs               | `journalctl -u sarthi -f`                     | `docker compose logs -f server`        |
| Rebuild            | `go build` + restart (seconds)                | image rebuild                          |
| Memory overhead    | none                                          | daemon + 3 containers (~150–250 MB)    |
| Reproducibility    | depends on the host                           | pinned in the image                    |

Native wins on visibility and on small boxes (≤1 GB RAM). Docker wins on
reproducibility and on hosts you do not want to modify.

## Prerequisites

1. Ubuntu 24.04, root access.
2. **A DNS A record for your domain pointing at the box's public IP.** Caddy
   cannot obtain a certificate without it, and the script refuses to run until
   it resolves — each failed ACME attempt burns a Let's Encrypt rate limit
   (5 failed validations per hostname per hour).
   ```bash
   dig +short api.example.com   # must print the VPS IP
   ```
3. `server/.env.prod`, filled in:
   ```bash
   cp .env.prod.example .env.prod
   ```
   | Variable            | Notes                                                       |
   | ------------------- | ----------------------------------------------------------- |
   | `DOMAIN`            | e.g. `api.example.com` — the A record above                  |
   | `POSTGRES_PASSWORD` | generate one: `openssl rand -base64 24`                      |
   | `FAST2SMS_API_KEY`  | Fast2SMS dashboard → Dev API → API Key                       |
   | `FAST2SMS_OTP_ID`   | a registered OTP template id                                 |

   `.env.prod` is gitignored. Keep it that way — it holds live credentials.

## Run it

```bash
git clone git@github.com:VedanshuGoyal/Sarthi.git
cd Sarthi/server/deploy
sudo ./setup-vps.sh
```

Roughly 5 minutes on a fresh box. It ends by printing your `API_BASE_URL`,
which is what the release APK build needs.

Every phase is idempotent — **re-running is the intended way to apply
changes.** Rotate `POSTGRES_PASSWORD` in `.env.prod`, re-run, done.

To run part of it:

```bash
sudo ./setup-vps.sh build service     # rebuild + restart only
sudo ./setup-vps.sh migrations        # apply new migrations
```

| Phase        | What it does                                                              |
| ------------ | ------------------------------------------------------------------------- |
| `go`         | Installs Go (pinned) to `/usr/local/go`; apt's is too old for `go.mod`     |
| `postgres`   | Adds the PGDG repo, installs PostgreSQL 17 (matches the Docker image tag)  |
| `database`   | Creates/updates the `sarthi` role + database, verifies TCP auth            |
| `migrations` | Replays `../migrations/*.up.sql` in order                                  |
| `build`      | `go build` → `/opt/sarthi/bin/sarthi-server`                               |
| `service`    | Creates the `sarthi` user, writes `/etc/sarthi/sarthi.env`, installs the unit |
| `caddy`      | Installs Caddy, writes the Caddyfile + `$DOMAIN` drop-in                   |
| `firewall`   | Opens 80/443 in ufw (Postgres stays closed)                                |
| `verify`     | Health-checks locally, then over HTTPS, polling until the cert is issued   |

## Shipping updates

```bash
sudo ./redeploy.sh --pull
```

Builds to a temp path (a broken compile can't clobber the running binary),
swaps it in, restarts, health-checks, and **rolls back automatically** if the
new binary fails. Migrations are deliberately not automatic — run
`sudo ./setup-vps.sh migrations` when a release adds one.

## Operating it

```bash
journalctl -u sarthi -f                    # live server logs
journalctl -u caddy -f                     # TLS issuance/renewal, proxy errors
tail -f /var/log/caddy/sarthi.log | jq     # HTTP access log
sudo -u postgres psql sarthi               # DB shell
systemctl status sarthi caddy postgresql   # service health
```

Useful queries:

```bash
sudo -u postgres psql sarthi -c \
  "SELECT id, phone_e164, name, created_at FROM users ORDER BY created_at DESC LIMIT 20;"
```

## What goes where

| Path                                        | Purpose                                  |
| ------------------------------------------- | ---------------------------------------- |
| `/opt/sarthi/bin/sarthi-server`             | the compiled binary (`.prev` = rollback) |
| `/etc/sarthi/sarthi.env`                    | server secrets, root-only `0600`         |
| `/etc/sarthi/caddy.env`                     | just `DOMAIN=…`, read by caddy.service   |
| `/etc/systemd/system/sarthi.service`        | the unit (copy of `sarthi.service` here) |
| `/etc/systemd/system/caddy.service.d/domain.conf` | points Caddy at `caddy.env`        |
| `/etc/caddy/Caddyfile`                      | copy of `Caddyfile` here                 |
| `/var/log/caddy/sarthi.log`                 | JSON access log, rolled at 10 MiB        |
| `/var/lib/postgresql/17/main`               | database files — **back this up**        |

## Gotchas

Both of these cost real debugging time during the first deploy; the scripts
now handle them, but they are worth recognising.

**`ufw` silently breaks certificate issuance.** Many VPS images ship ufw
active with a default-deny policy and only :22 open. Caddy binds :80/:443
fine and logs nothing unusual, but ACME fails with:

```
"detail":"<ip>: Timeout during connect (likely firewall problem)"
```

The `firewall` phase opens both ports. If your provider *also* has a cloud
firewall (Vultr, AWS security groups, Hetzner), open 80/443 there too — the
host firewall is only half the path.

**Never run `caddy validate` or `caddy run` as root once file logging is
configured.** Doing so creates `/var/log/caddy/sarthi.log` owned by
`root:root` with mode `0600`. The service runs as `caddy`, so it then cannot
open its own log file and dies at startup with a bare:

```
open /var/log/caddy/sarthi.log: permission denied
```

Confusingly the *directory* is writable — only the pre-existing *file* is not.
The `caddy` phase re-asserts `chown -R caddy:caddy /var/log/caddy` on every
run, so re-running the script fixes it.

**Migrations have no version tracking.** Replaying them is safe today only
because every one uses `CREATE TABLE/INDEX IF NOT EXISTS`. A migration that
alters or drops something would break that assumption — switch to
`golang-migrate` before writing one:

```bash
migrate -path ../migrations -database "$DATABASE_URL" up
```

## Before this is really production

Carried over from `../README.md`, still outstanding:

- `/users` is **unauthenticated and publicly reachable** — it returns every
  account to anyone who asks. Put it behind admin auth before real signups.
- Expired session rows are never swept; add a periodic job.
- Nothing backs up `/var/lib/postgresql/17/main`. Set up `pg_dump` on a timer
  plus off-box storage.
- The server binds `:8080` on all interfaces. It is not in the firewall's
  allow-list so it is unreachable from outside, but binding `127.0.0.1:8080`
  via `ADDR` would be defence in depth.

## Uninstalling

```bash
systemctl disable --now sarthi caddy
rm -rf /opt/sarthi /etc/sarthi /etc/systemd/system/sarthi.service \
       /etc/systemd/system/caddy.service.d
systemctl daemon-reload
# Postgres and its data are left alone on purpose — drop them deliberately:
#   sudo -u postgres dropdb sarthi && sudo -u postgres dropuser sarthi
```
