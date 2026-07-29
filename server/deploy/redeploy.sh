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

log "Swapping in the new binary"
[[ -f "$BINARY" ]] && cp -a "$BINARY" "$BINARY.prev"
install -m 755 "$TMP_BINARY" "$BINARY"

log "Restarting sarthi"
systemctl restart sarthi.service
sleep 2

if ! curl -fsS --max-time 10 localhost:8080/healthz >/dev/null 2>&1; then
	printf '\033[1;33m    health check failed — rolling back\033[0m\n' >&2
	if [[ -f "$BINARY.prev" ]]; then
		install -m 755 "$BINARY.prev" "$BINARY"
		systemctl restart sarthi.service
		die "rolled back to the previous binary. Logs: journalctl -u sarthi -n 50"
	fi
	die "no previous binary to roll back to. Logs: journalctl -u sarthi -n 50"
fi

log "Deployed. $(curl -s localhost:8080/healthz)"
