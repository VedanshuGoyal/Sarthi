# Checking local services (Docker · Postgres · Go)

Quick reference for confirming the Sarthi backend stack is running locally.
There are three moving parts:

| Component | What it is | Where | Port |
|-----------|------------|-------|------|
| 🐳 Docker → Postgres | `postgres:17` container (`server-db-1`) — durable data | `server/docker-compose.yml` | `5432` |
| 🐘 Postgres | Source of truth (users, rides, financials) | inside the container | `5432` |
| 🟢 Go server | REST + WebSocket API (`cmd/server`) | `server/` | `8080` |

Run these from the repo root (`/Users/friend/Dev/Sarthi`).

---

## 1. Docker / Postgres container

```bash
docker ps                                          # is the container up?
docker compose -f server/docker-compose.yml ps     # scoped to this project
docker logs server-db-1 --tail 20                  # DB logs if something's wrong
```

Healthy output looks like:

```
NAMES         IMAGE         STATUS                 PORTS
server-db-1   postgres:17   Up 10 days (healthy)   0.0.0.0:5432->5432/tcp
```

## 2. Postgres actually accepting queries

```bash
docker exec server-db-1 pg_isready -U sarthi -d sarthi          # → "accepting connections"
docker exec -it server-db-1 psql -U sarthi -d sarthi -c '\dt'   # list tables
```

Expected: `/var/run/postgresql:5432 - accepting connections`, and the `users`
table listed. (DB name / user / password are all `sarthi` — see
`docker-compose.yml`.)

## 3. Go server

```bash
lsof -iTCP:8080 -sTCP:LISTEN     # is something listening on :8080?
pgrep -fl 'cmd/server'           # is the process alive?
curl -s -i localhost:8080/healthz
```

Healthy response:

```
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"ok"}
```

### Available routes (`internal/api/router.go`)

| Method | Path | Purpose |
|--------|------|---------|
| GET  | `/healthz`         | liveness check |
| POST | `/auth/otp`        | request an OTP |
| POST | `/auth/otp/verify` | verify an OTP |
| POST | `/auth/register`   | register a user |
| GET  | `/users`           | list users |

---

## Starting things up (if any are down)

```bash
# Postgres
docker compose -f server/docker-compose.yml up -d

# Go server (from the server/ dir)
cd server && go run ./cmd/server
```

## One-shot health check

```bash
docker exec server-db-1 pg_isready -U sarthi -d sarthi \
  && curl -s localhost:8080/healthz \
  && echo "  ✅ all up"
```

> Note: `lsof -iTCP:5432` may show an `ssh` process — that's just an SSH tunnel
> forwarding to the DB container, not the real listener. The actual Postgres
> listener is inside Docker.
