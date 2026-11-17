#!/usr/bin/env bash
#
# Ship a new version of the server to an already-provisioned box.
#
#   sudo ./redeploy.sh          # rebuild from the current working tree
#   sudo ./redeploy.sh --pull   # git pull first, then rebuild
#
# Rebuilds the binary, restarts the unit, and rolls back to the previous binary
# if the new one fails its health check. Does not touch Postgres, Caddy, or the
# firewall — use setup-vps.sh for those.
#
# New migrations are NOT applied automatically; run them explicitly:
#   sudo ./setup-vps.sh migrations

set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$DEPLOY_DIR")"
BINARY="/opt/sarthi/bin/sarthi-server"
GO="/usr/local/go/bin/go"

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (try: sudo $0)"
[[ -x "$GO" ]] || die "Go not found at $GO — run setup-vps.sh go"

if [[ "${1:-}" == "--pull" ]]; then
	log "Pulling latest"
	git -C "$SERVER_DIR" pull --ff-only
fi

log "Building"
# Build to a temp path first: a failed compile then leaves the running binary
# untouched instead of truncating it.
TMP_BINARY="$(mktemp /tmp/sarthi-server.XXXXXX)"
trap 'rm -f "$TMP_BINARY"' EXIT
( cd "$SERVER_DIR" && "$GO" build -o "$TMP_BINARY" ./cmd/server ) || die "build failed — nothing was deployed"

# The nightly backup's off-box uploader and script (sarthi-backup.timer).
# Not part of the health-checked swap below: a failure here only warns.
if ( cd "$SERVER_DIR" && "$GO" build -o /opt/sarthi/bin/sarthi-backup-upload.new ./cmd/backup-upload ); then
	mv /opt/sarthi/bin/sarthi-backup-upload.new /opt/sarthi/bin/sarthi-backup-upload
	install -D -m 750 "$DEPLOY_DIR/backup.sh" /opt/sarthi/deploy/backup.sh
	install -D -m 750 "$DEPLOY_DIR/watchdog.sh" /opt/sarthi/deploy/watchdog.sh
else
	printf 'warning: backup uploader did not build; nightly off-box copies will fail\n' >&2
fi

log "Swapping in the new binary"
[[ -f "$BINARY" ]] && cp -a "$BINARY" "$BINARY.prev"
install -m 755 "$TMP_BINARY" "$BINARY"

# wait_for <path> <seconds> — poll until the endpoint answers 2xx.
wait_for() {
	local path=$1 deadline=$((SECONDS + $2))
	while ((SECONDS < deadline)); do
		curl -fsS --max-time 5 "localhost:8080$path" >/dev/null 2>&1 && return 0
		sleep 1
	done
	return 1
}

log "Restarting sarthi"
systemctl restart sarthi.service

# /readyz = up and reaching Postgres. The previous binary may predate
# /readyz, so after a rollback only /healthz is checked.
if ! wait_for /readyz 30; then
	printf '\033[1;33m    readiness check failed — rolling back\033[0m\n' >&2
	if [[ -f "$BINARY.prev" ]]; then
		install -m 755 "$BINARY.prev" "$BINARY"
		systemctl restart sarthi.service
		wait_for /healthz 30 || die "rollback did not come up either. Logs: journalctl -u sarthi -n 50"
		die "rolled back to the previous binary. Logs: journalctl -u sarthi -n 50"
	fi
	die "no previous binary to roll back to. Logs: journalctl -u sarthi -n 50"
fi

log "Deployed. $(curl -s localhost:8080/readyz)"
