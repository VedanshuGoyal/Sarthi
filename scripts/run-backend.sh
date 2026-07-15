#!/usr/bin/env bash
#
# run-backend.sh — start the Sarthi backend: Postgres (Docker) + Go API server.
#
# Brings up the postgres:17 container (idempotent — no-op if already running),
# waits until it's accepting connections, then runs the Go server on :8080.
# Ctrl-C stops the Go server; the DB container keeps running (stop it with
# `docker compose -f server/docker-compose.yml down`).
#
#   ./scripts/run-backend.sh
#
# Override the DSN or listen address via the environment if needed:
#   DATABASE_URL=... ADDR=:9090 ./scripts/run-backend.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/server"

# Load local secrets (Fast2SMS keys, DSN overrides) if present. This file is
# gitignored — see server/.env. Values already in the environment win, since the
# `:=` defaults below only fill in what's unset.
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${DATABASE_URL:=postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable}"
: "${ADDR:=:8080}"
export DATABASE_URL ADDR

# Pick whichever Compose is installed: the `docker compose` v2 plugin if
# present, otherwise the standalone `docker-compose` binary.
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "❌ Neither 'docker compose' nor 'docker-compose' is installed." >&2
  exit 1
fi

# Docker needs a running daemon. On this setup that's Colima.
if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon not reachable. Start it first (e.g. 'colima start')." >&2
  exit 1
fi

echo "🐳 Ensuring Postgres is up..."
"${COMPOSE[@]}" -f docker-compose.yml up -d

echo "⏳ Waiting for Postgres to accept connections..."
for i in $(seq 1 30); do
  if docker exec server-db-1 pg_isready -U sarthi -d sarthi >/dev/null 2>&1; then
    echo "🐘 Postgres ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "❌ Postgres did not become ready in time." >&2
    exit 1
  fi
  sleep 1
done

# Apply migrations in order. They're idempotent (CREATE ... IF NOT EXISTS), so
# re-running on every boot is safe and picks up new ones (e.g. recent_pickups)
# automatically. Only *.up.sql is applied — never the .down.sql rollbacks.
# Piped through the DB container's psql, so no host psql install is needed.
echo "📜 Applying migrations..."
shopt -s nullglob
for migration in migrations/*.up.sql; do
  echo "   → $(basename "$migration")"
  if ! docker exec -i server-db-1 \
      psql -v ON_ERROR_STOP=1 -U sarthi -d sarthi <"$migration" >/dev/null; then
    echo "❌ Migration failed: $migration" >&2
    exit 1
  fi
done
shopt -u nullglob

echo "🟢 Starting Go server on ${ADDR} (Ctrl-C to stop)..."
exec go run ./cmd/server
