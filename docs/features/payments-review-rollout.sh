#!/usr/bin/env bash
#
# payments-review rollout — the server fixes from the night of 21 Nov 2026
# (no migration). Built from .claude/skills/sarthi-feature/rollout-template.sh.
#
#   bash docs/features/payments-review-rollout.sh
#
# What ships (HUMAN REVIEW REQUIRED: payments):
#   - fixes from the Fable review of the money paths (fix/payments-review):
#     no booking in two open orders, an unknown gateway state never counts
#     as paid, row locks between checkout and settle-by-hand, the
#     paid-twice list shows the right ride and refund, payouts need the
#     shown amount, night charge follows the booked start, a retried
#     "end trip" returns the trip;
#   - one receipt for a payment that paid several bookings (read-only);
#   - multi-stop bookings name the car, required only from user app
#     build 10 (1.6.0 is +9, so released apps are unaffected);
#   - a push FCM couldn't take for a moment (network, 429, 5xx) is tried
#     again after 1 s and 4 s.
#
# Steps (stops at the first failure):
#   1. local HEAD == origin/main
#   2. on prod: git pull, check the commit, pg_dump backup
#   3. server/deploy/redeploy.sh — builds, restarts, waits for /readyz,
#      rolls back by itself on failure
#   4. smoke checks from outside
#
# Rollback: git checkout <previous> && server/deploy/redeploy.sh on the box
# (no schema change, so nothing to undo in the database).
set -euo pipefail

SLUG="payments-review"
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

REMOTE_SHA="$(gh api repos/VedanshuGoyal/Sarthi/commits/main --jq .sha)" || die "gh api failed"
[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)" ] \
  || die "uncommitted changes in tracked files — commit or stash first"
[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$REMOTE_SHA" ] \
  || die "local HEAD is not origin/main ($REMOTE_SHA) — push (or pull) first"
WANT="${REMOTE_SHA:0:12}"
log "Shipping $SLUG at $WANT"

ssh vultr bash -s -- "$STAMP" "$WANT" <<'REMOTE'
set -euo pipefail
STAMP=$1; WANT=$2
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


echo "==> redeploy"
server/deploy/redeploy.sh
REMOTE

log "Smoke checks"
expect_status 200 "$API/healthz"
expect_status 200 "$API/readyz"
expect_status 401 "$API/admin/stats"
expect_status 401 -X POST "$API/me/bookings/00000000-0000-4000-8000-000000000000/end"
expect_status 401 -X POST "$API/me/bookings/00000000-0000-4000-8000-000000000000/payment"
expect_status 401 "$API/admin/payments/attention"

log "Done: $SLUG at $WANT (backup /root/backups/sarthi-$STAMP.sql.gz)"
