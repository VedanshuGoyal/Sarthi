#!/usr/bin/env bash
#
# carry-dues rollout — unpaid rides and fees are carried into the customer's
# next payment instead of blocking their next booking, and trips that run
# past the booked hours are charged for the extra time (17 Nov 2026,
# docs/features/cancellation-charges.md). Built from
# .claude/skills/sarthi-feature/rollout-template.sh.
#
#   bash docs/features/carry-dues-rollout.sh
#
# Steps (stops at the first failure):
#   1. local HEAD == origin/main
#   2. on prod: git pull, check the commit, pg_dump backup
#   3. migration 0031 (payment_order_items, backfilled from existing orders)
#   4. server/deploy/redeploy.sh — builds, restarts, waits for /readyz,
#      rolls back by itself on failure
#   5. smoke checks from outside
#
# Rollback: binary — automatic in redeploy.sh, or git checkout <previous> &&
# server/deploy/redeploy.sh (the previous build ignores the new table).
# Database — 0031 has a .down.sql; paid bookings keep paid_at either way.
set -euo pipefail

SLUG="carry-dues"
MIGRATIONS=(0031_payment_order_items.up.sql)
API="https://api.mojud.life"
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
expect_status() {
  local want=$1; shift
  local got
  got="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@")"
  [ "$got" = "$want" ] || die "$* → HTTP $got (want $want)"
  echo "  ok $want  ${*: -1}"
}

for m in "${MIGRATIONS[@]}"; do
  [ -f "$REPO_ROOT/server/migrations/$m" ] || die "no such migration: server/migrations/$m"
done
REMOTE_SHA="$(gh api repos/VedanshuGoyal/Sarthi/commits/main --jq .sha)" || die "gh api failed"
[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ] \
  || die "uncommitted changes in tracked files — commit or stash first"
[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$REMOTE_SHA" ] \
  || die "local HEAD is not origin/main ($REMOTE_SHA) — push (or pull) first"
WANT="${REMOTE_SHA:0:12}"
log "Shipping $SLUG at $WANT"

ssh vultr bash -s -- "$STAMP" "$WANT" "${MIGRATIONS[@]}" <<'REMOTE'
set -euo pipefail
STAMP=$1; WANT=$2; shift 2
cd /root/mojud/Sarthi

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

set -a; . server/.env.prod; set +a
for m in "$@"; do
  echo "==> migration $m"
  PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U sarthi -d sarthi \
    -v ON_ERROR_STOP=1 -1 -f "server/migrations/$m"
done
echo "    order items backfilled: $(PGPASSWORD="$POSTGRES_PASSWORD" psql -h localhost -U sarthi -d sarthi -At \
  -c 'SELECT count(*) FROM payment_order_items')"

echo "==> redeploy"
server/deploy/redeploy.sh
REMOTE

log "Smoke checks"
expect_status 200 "$API/healthz"
expect_status 200 "$API/readyz"
expect_status 401 "$API/admin/stats"
expect_status 401 -X POST "$API/me/bookings/00000000-0000-4000-8000-000000000000/end"

log "Done: $SLUG at $WANT (backup /root/backups/sarthi-$STAMP.sql.gz)"
