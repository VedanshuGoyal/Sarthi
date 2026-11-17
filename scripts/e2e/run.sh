#!/usr/bin/env bash
# run.sh — end-to-end check of the API against a local server, no real
# third parties: dev OTP (123456), a fake PhonePe (:8098), the server (:8097),
# the local Docker Postgres (server-db-1, started by scripts/run-backend.sh).
# The driver is made "verified" by SQL (no Surepass fake). Never point this
# at prod.
#
#   ./scripts/e2e/run.sh            # build, start, run e2e.py, stop
#   MIN_BUILD_USER_APP=100 ./scripts/e2e/run.sh extras.py   # 426 gate checks
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; export E2E_TMP="$TMP"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$TMP"' EXIT

(cd "$ROOT/server" && go build -o "$TMP/sarthi-server" ./cmd/server)
python3 -I "$HERE/fake_phonepe.py" 8098 >"$TMP/phonepe.log" 2>&1 &

unset FAST2SMS_API_KEY FAST2SMS_OTP_ID SUREPASS_TOKEN FCM_CREDENTIALS_FILE
export DATABASE_URL="${DATABASE_URL:-postgres://sarthi:sarthi@localhost:5432/sarthi?sslmode=disable}"
export ALLOW_DEV_DEFAULTS=1 ADMIN_TOKEN=dev-admin-token-0123456789abcdef0123 ADDR=:8097
export STORAGE_BACKEND=local STORAGE_LOCAL_DIR="$TMP/blobs"
export PHONEPE_CLIENT_ID=fake-client PHONEPE_CLIENT_SECRET=fake-secret PHONEPE_CLIENT_VERSION=1
export PHONEPE_MERCHANT_ID=FAKEMERCHANT PHONEPE_ENV=SANDBOX
export PHONEPE_TOKEN_URL=http://127.0.0.1:8098/v1/oauth/token PHONEPE_BASE_URL=http://127.0.0.1:8098
(cd "$ROOT/server" && "$TMP/sarthi-server" >"$TMP/server.log" 2>&1) &
for _ in $(seq 60); do curl -fsS localhost:8097/readyz >/dev/null 2>&1 && break; sleep 1; done

python3 -I "$HERE/${1:-e2e.py}" || { echo "--- server log tail"; tail -30 "$TMP/server.log"; exit 1; }
