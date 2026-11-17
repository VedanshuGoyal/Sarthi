#!/usr/bin/env bash
# backup.sh — nightly PostgreSQL backup for Sarthi (run by sarthi-backup.timer).
#
#   1. pg_dump the database to /var/backups/sarthi/sarthi-<stamp>.sql.gz (0600)
#   2. keep the newest $KEEP local dumps
#   3. copy the new dump off the box to the S3/R2 bucket (backups/db/)
#
# A failed off-box copy fails the unit (visible in `systemctl --failed`) but
# keeps the local dump. Restore drill: see deploy/README.md.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/sarthi/sarthi.env}"
DIR="${BACKUP_DIR:-/var/backups/sarthi}"
KEEP="${KEEP:-14}"
UPLOADER="${UPLOADER:-/opt/sarthi/bin/sarthi-backup-upload}"

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
: "${DATABASE_URL:?DATABASE_URL missing from $ENV_FILE}"

install -d -m 700 "$DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DIR/sarthi-$STAMP.sql.gz"

umask 077
pg_dump --no-owner --dbname="$DATABASE_URL" | gzip -9 > "$OUT.partial"
mv "$OUT.partial" "$OUT"
echo "dump: $OUT ($(stat -c %s "$OUT") bytes)"

# Keep the newest $KEEP dumps.
ls -1t "$DIR"/sarthi-*.sql.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f --

if [[ -x "$UPLOADER" && -n "${S3_BUCKET:-}" ]]; then
	"$UPLOADER" "$OUT"
else
	echo "warning: no off-box copy (uploader or S3_BUCKET missing)" >&2
	exit 1
fi
