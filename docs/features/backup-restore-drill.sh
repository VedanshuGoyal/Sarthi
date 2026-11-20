#!/usr/bin/env bash
#
# backup-restore-drill — proves the nightly backups can be restored, as
# server/deploy/README.md asks (once, then quarterly). Run from the laptop:
#
#   bash docs/features/backup-restore-drill.sh
#
# On the box it loads the newest dump in /var/backups/sarthi into a scratch
# database (sarthi_restore_test), checks it has the newest schema and the
# same rows as the live database had, then drops the scratch database. The
# live `sarthi` database is only read (row counts).
set -euo pipefail

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }

log "Restore drill on the box"
ssh -o BatchMode=yes -o ConnectTimeout=15 vultr bash -s <<'REMOTE'
set -euo pipefail
DB=sarthi_restore_test
DUMP="$(ls -1t /var/backups/sarthi/sarthi-*.sql.gz 2>/dev/null | head -1)"
[ -n "$DUMP" ] || { echo "no dump in /var/backups/sarthi" >&2; exit 1; }
echo "    newest dump: $DUMP ($(stat -c %s "$DUMP") bytes, $(stat -c %y "$DUMP" | cut -d. -f1))"
gzip -t "$DUMP"
pg() { sudo -u postgres psql -X -q -At "$@"; }
cleanup() { sudo -u postgres dropdb --if-exists "$DB"; }
trap cleanup EXIT
cleanup
sudo -u postgres createdb "$DB"
zcat "$DUMP" | sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d "$DB" >/dev/null
# The newest migrations (0030, 0031) must be in the dump.
pg -d "$DB" -c "SELECT 1 FROM information_schema.columns WHERE table_name = 'bookings' AND column_name = 'cancellation_fee_paise'" | grep -q 1 \
  || { echo "restored schema lacks 0030" >&2; exit 1; }
pg -d "$DB" -c "SELECT to_regclass('public.payment_order_items') IS NOT NULL" | grep -q t \
  || { echo "restored schema lacks 0031" >&2; exit 1; }
# Rows in the dump vs rows created by the dump's time in the live database.
STAMP="$(basename "$DUMP" .sql.gz | sed 's/^sarthi-//')"
AT="$(date -d "${STAMP:0:8} ${STAMP:9:2}:${STAMP:11:2}:${STAMP:13:2}" '+%F %T%z')"
printf '    %-22s %8s %8s\n' table restored "live@dump"
bad=0
for t in users drivers bookings payment_orders payment_order_items driver_payouts; do
  r="$(pg -d "$DB" -c "SELECT count(*) FROM $t")"
  l="$(pg -d sarthi -c "SELECT count(*) FROM $t WHERE created_at <= '$AT'" 2>/dev/null || pg -d sarthi -c "SELECT count(*) FROM $t")"
  flag=""; [ "$r" = "$l" ] || { flag="  <- differs"; bad=1; }
  printf '    %-22s %8s %8s%s\n' "$t" "$r" "$l" "$flag"
done
[ "$bad" = 0 ] && echo "    ok: the dump restores and matches the live rows at its time" \
  || echo "    note: a difference can be a row deleted since (account erasure); look before worrying"
REMOTE
log "Done (scratch database dropped)"
