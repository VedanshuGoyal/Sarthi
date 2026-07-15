#!/usr/bin/env bash
#
# status.sh — one-shot health check for the backend stack.
# Reports whether Docker/Postgres and the Go server are up. Read-only.
#
#   ./scripts/status.sh
set -uo pipefail

: "${DATABASE_URL:=postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable}"

ok()   { printf '  ✅ %s\n' "$1"; }
bad()  { printf '  ❌ %s\n' "$1"; }

# Tables the migrations create — keep in sync with server/migrations/*.up.sql.
EXPECTED_TABLES=(users sessions recent_pickups)

echo "🐳 Docker / Postgres container:"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^server-db-1$'; then
  ok "server-db-1 running"
  if docker exec server-db-1 pg_isready -U sarthi -d sarthi >/dev/null 2>&1; then
    ok "Postgres accepting connections"

    echo "📋 Schema (migrations applied?):"
    for t in "${EXPECTED_TABLES[@]}"; do
      count=$(docker exec server-db-1 \
        psql -U sarthi -d sarthi -tAc "SELECT count(*) FROM \"$t\"" 2>/dev/null \
        | tr -d '[:space:]')
      if [ -n "$count" ]; then
        ok "$t ($count rows)"
      else
        bad "$t missing  (apply migrations: ./scripts/run-backend.sh)"
      fi
    done
  else
    bad "Postgres not accepting connections yet"
  fi
else
  bad "server-db-1 not running  (start: ./scripts/run-backend.sh)"
fi

echo "🟢 Go server (:8080):"
if curl -sf localhost:8080/healthz >/dev/null 2>&1; then
  ok "/healthz -> $(curl -s localhost:8080/healthz)"
else
  bad "not responding  (start: ./scripts/run-backend.sh)"
fi
