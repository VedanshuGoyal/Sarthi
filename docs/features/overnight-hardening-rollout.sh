#!/usr/bin/env bash
#
# overnight-hardening rollout — the 17 Nov 2026 production-readiness work
# (branch overnight/production-ready). Built from
# .claude/skills/sarthi-feature/rollout-template.sh.
#
# The OWNER runs this from the laptop, after reviewing the branch, merging it
# to main and pushing:
#
#   bash docs/features/overnight-hardening-rollout.sh
#
# What it does, in order (stops at the first failure):
#   1. local HEAD == origin/main (what you reviewed is what ships)
#   2. on prod: git pull, check the commit, pg_dump backup
#   3. secrets: if prod has no DOCUMENT_ENCRYPTION_KEY/PEPPER, generate them,
#      add them to /etc/sarthi/sarthi.env and server/.env.prod (old files kept
#      as .bak-<stamp>), and re-seal the stored bank numbers (cmd/rekey) —
#      the new server refuses to boot without real keys
#   4. migrations in order, each in one transaction, as the sarthi user
#   5. systemd units: sarthi.service (memory caps, never-give-up restarts),
#      nightly backup timer, watchdog timer; Telegram alerts config
#   6. server/deploy/redeploy.sh — builds, restarts, waits for /readyz, rolls
#      back by itself on failure
#   7. first backup run (checks the off-box R2 copy), smoke checks from outside
#   8. scripts/publish-apps.sh if PUBLISH_APPS=1 (after the phone test)
#
# Rollback:
#   binary   — automatic in redeploy.sh; by hand: in /root/mojud/Sarthi,
#              git checkout <previous commit> && server/deploy/redeploy.sh.
#              Older binaries read the new keys too, so leave them set.
#   database — each migration has a .down.sql; or restore the backup printed
#              below. 0020 (hashed session tokens) is one-way: rolling back
#              past it signs everyone out.
#   secrets  — the .bak-<stamp> env files; rekey back with
#              OLD_DOCUMENT_ENCRYPTION_KEY=<new> DOCUMENT_ENCRYPTION_KEY=<old>
set -euo pipefail

SLUG="overnight-hardening"
MIGRATIONS=(
  0015_kyc_rejection_hold.up.sql
  0016_payment_checkout_token.up.sql
  0017_aadhaar_identity.up.sql
  0018_money_fks_restrict.up.sql
  0019_kyc_cleared_selfie.up.sql
  0020_hash_session_tokens.up.sql
  0021_booking_events.up.sql
  0022_driver_duty.up.sql
  0025_booking_payment_due_dedupe.up.sql
  0026_admin_actions.up.sql
  0027_payment_orders_pending.up.sql
  0028_consent_and_erasure.up.sql
  0029_retention_indexes.up.sql
)
PUBLISH_APPS="${PUBLISH_APPS:-0}"   # 1 = publish scripts/*-release.apk afterwards
API="https://api.mojud.life"
ADMIN_TOKEN_FILE="$HOME/Documents/MOJUD_Keys/sarthi-admin-token.txt"
TG_ENV="$HOME/.config/cgwb-tg.env"  # MOJUD Build bot (token + chat id) for alerts

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# expect_status <code> <curl args…> — fails unless the response has that status.
expect_status() {
  local want=$1; shift
  local got
  got="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@")"
  [ "$got" = "$want" ] || die "$* → HTTP $got (want $want)"
  echo "  ok $want  ${*: -1}"
}

smoke() {
  expect_status 200 "$API/healthz"
  expect_status 200 "$API/readyz"
  # Registration without a verified OTP is refused (no SMS is sent, no account made).
  expect_status 401 -X POST -H 'Content-Type: application/json' \
    -d '{"phoneE164":"+916000000001","name":"Smoke Test","email":"smoke@example.com","dateOfBirth":"1990-01-01"}' \
    "$API/auth/register"
  expect_status 401 -X POST -H 'Content-Type: application/json' \
    -d '{"phoneE164":"+916000000001","name":"Smoke Test"}' "$API/driver/auth/register"
  expect_status 401 "$API/admin/stats"
  # CORS no longer reflects arbitrary origins.
  if curl -s -D - -o /dev/null --max-time 15 -H 'Origin: https://evil.example' "$API/healthz" \
      | grep -qi '^access-control-allow-origin'; then
    die "CORS still reflects arbitrary origins"
  fi
  echo "  ok CORS allow-list"
  curl -s -D - -o /dev/null --max-time 15 "$API/healthz" | grep -qi '^x-content-type-options: nosniff' \
    || die "security headers missing"
  echo "  ok security headers"
  [ -r "$ADMIN_TOKEN_FILE" ] || die "can't read $ADMIN_TOKEN_FILE"
  curl -fsS --max-time 15 -H "Authorization: Bearer $(cat "$ADMIN_TOKEN_FILE")" "$API/admin/stats" \
    | python3 -m json.tool | head -20
}

# --- 1. what ships is what was pushed ----------------------------------------
for m in "${MIGRATIONS[@]}"; do
  [ -f "$REPO_ROOT/server/migrations/$m" ] || die "no such migration: server/migrations/$m"
done
# `git fetch` can hang from some shells; compare with GitHub's view instead.
REMOTE_SHA="$(gh api repos/VedanshuGoyal/Sarthi/commits/main --jq .sha)" || die "gh api failed"
[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ] \
  || die "uncommitted changes in tracked files — commit or stash first"
[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$REMOTE_SHA" ] \
  || die "local HEAD is not origin/main ($REMOTE_SHA) — push (or pull) first"
WANT="${REMOTE_SHA:0:12}"
log "Shipping $SLUG at $WANT"

# --- 2–4. on the server: pull, backup, secrets + rekey, migrations -------------
ssh vultr bash -s -- "$STAMP" "$WANT" "${MIGRATIONS[@]}" <<'REMOTE'
set -euo pipefail
STAMP=$1; WANT=$2; shift 2
cd /root/mojud/Sarthi
GO=/usr/local/go/bin/go

echo "==> git pull"
git pull --ff-only
GOT="$(git rev-parse --short=12 HEAD)"
[ "$GOT" = "$WANT" ] || { echo "prod is at $GOT, expected $WANT" >&2; exit 1; }

echo "==> backup"
mkdir -p /root/backups
BACKUP="/root/backups/sarthi-$STAMP.sql.gz"
(cd /tmp && sudo -u postgres pg_dump sarthi) | gzip > "$BACKUP"
chmod 600 "$BACKUP"
echo "    $BACKUP ($(du -h "$BACKUP" | cut -f1))"

echo "==> completed rides never paid (they now block that customer's next booking;"
echo "    settle test rides as 'waived' from /admin → Bookings after the deploy)"
sudo -u postgres psql -d sarthi -At -c "SELECT count(*) FROM bookings WHERE status='completed' AND paid_at IS NULL"

echo "==> required secrets"
for v in FAST2SMS_API_KEY FAST2SMS_OTP_ID ADMIN_TOKEN; do
  grep -q "^$v=." /etc/sarthi/sarthi.env || { echo "missing $v in /etc/sarthi/sarthi.env" >&2; exit 1; }
done

if ! grep -q '^DOCUMENT_ENCRYPTION_KEY=.' /etc/sarthi/sarthi.env; then
  echo "==> generating DOCUMENT_ENCRYPTION_KEY + DOCUMENT_HASH_PEPPER (prod used the dev keys)"
  cp -p /etc/sarthi/sarthi.env "/etc/sarthi/sarthi.env.bak-$STAMP"
  cp -p server/.env.prod "server/.env.prod.bak-$STAMP"
  KEY="$(openssl rand -base64 32)"
  PEPPER="$(openssl rand -hex 32)"
  for f in /etc/sarthi/sarthi.env server/.env.prod; do
    printf '\nDOCUMENT_ENCRYPTION_KEY=%s\nDOCUMENT_HASH_PEPPER=%s\n' "$KEY" "$PEPPER" >> "$f"
  done
  echo "==> re-sealing stored bank numbers under the new key"
  ( set -a; . /etc/sarthi/sarthi.env; set +a; cd server && "$GO" run ./cmd/rekey )
else
  echo "    keys already set"
fi

if [ $# -gt 0 ]; then
  set -a; . server/.env.prod; set +a
  for m in "$@"; do
    echo "==> migration $m"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U sarthi -d sarthi \
      -v ON_ERROR_STOP=1 -1 -f "server/migrations/$m"
  done
fi

echo "==> systemd units"
diff -u /etc/systemd/system/sarthi.service server/deploy/sarthi.service || true
install -m 644 server/deploy/sarthi.service /etc/systemd/system/sarthi.service
install -m 644 server/deploy/sarthi-backup.service server/deploy/sarthi-backup.timer \
  server/deploy/sarthi-watchdog.service server/deploy/sarthi-watchdog.timer /etc/systemd/system/
systemctl daemon-reload

echo "==> redeploy"
server/deploy/redeploy.sh

echo "==> timers"
systemctl enable --now sarthi-backup.timer sarthi-watchdog.timer
echo "==> first backup (local + off-box)"
systemctl start sarthi-backup.service || true
journalctl -u sarthi-backup -n 8 --no-pager
REMOTE

# --- 5b. Telegram alerts config (token stays out of the repo and the log) ---------
if [ -r "$TG_ENV" ]; then
  log "Alerts config"
  ( set -a; . "$TG_ENV"; set +a
    printf 'TELEGRAM_BOT_TOKEN=%s\nTELEGRAM_CHAT_ID=%s\n' "${TG_TOKEN:?}" "${TG_CHAT:?}" ) \
    | ssh vultr 'umask 077; cat > /etc/sarthi/alerts.env && grep -c "=." /etc/sarthi/alerts.env'
else
  echo "no $TG_ENV — create /etc/sarthi/alerts.env on the box by hand for alerts"
fi

# --- 7. from outside ----------------------------------------------------------
log "Smoke checks"
smoke

cat <<'EOF'

Manual, once (not automated: the live Caddyfile also serves other sites):
  in the api.mojud.life block of /etc/caddy/Caddyfile add
      request_body {
          max_size 13MB
      }
  then: caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && systemctl reload caddy
EOF

# --- 8. apps ------------------------------------------------------------------
if [ "$PUBLISH_APPS" = 1 ]; then
  log "Publishing APKs"
  "$REPO_ROOT/scripts/publish-apps.sh"
fi

log "Done: $SLUG at $WANT (backup /root/backups/sarthi-$STAMP.sql.gz)"
