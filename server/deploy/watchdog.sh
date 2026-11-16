#!/usr/bin/env bash
# watchdog.sh — tells the owner on Telegram when Sarthi needs a person
# (run every 2 minutes by sarthi-watchdog.timer, as root).
#
# Alerts when: /readyz fails (and again when it recovers); the server logs an
# ERROR (e.g. "ride paid twice; refund this order by hand", SMS provider
# rejecting sends); the nightly backup unit failed; the disk is over 90%.
# Each kind of alert repeats at most every 30 minutes.
#
# Needs /etc/sarthi/alerts.env (root, 0600):
#   TELEGRAM_BOT_TOKEN=...   TELEGRAM_CHAT_ID=...
# A box-level outage can't be seen from the box itself: pair this with an
# external uptime monitor on https://api.mojud.life/readyz.
set -uo pipefail

ALERTS_ENV="${ALERTS_ENV:-/etc/sarthi/alerts.env}"
STATE="${STATE_DIR:-/var/lib/sarthi-watchdog}"
API="${API:-http://localhost:8080}"
REPEAT_AFTER=1800

[[ -r "$ALERTS_ENV" ]] || { echo "no $ALERTS_ENV; nothing to alert to" >&2; exit 0; }
set -a
# shellcheck disable=SC1090
. "$ALERTS_ENV"
set +a
install -d -m 700 "$STATE"
now=$(date +%s)
host=$(hostname)

send() {
	curl -fsS --max-time 10 -o /dev/null \
		"${TELEGRAM_API:-https://api.telegram.org}/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
		--data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
		--data-urlencode "text=$1" || echo "telegram send failed" >&2
}

# alert <kind> <text> — send unless the same kind was sent in the last 30 min.
alert() {
	local f="$STATE/alert-$1" last=0
	[[ -f "$f" ]] && last=$(<"$f")
	((now - last < REPEAT_AFTER)) && return 0
	echo "$now" >"$f"
	send "⚠️ Sarthi ($host): $2"
}

# 1. Readiness, with a recovery note.
if curl -fsS --max-time 5 "$API/readyz" >/dev/null 2>&1; then
	if [[ -f "$STATE/down" ]]; then
		rm -f "$STATE/down" "$STATE/alert-down"
		send "✅ Sarthi ($host): API is ready again"
	fi
else
	touch "$STATE/down"
	alert down "API not ready (/readyz failed). journalctl -u sarthi -n 50"
fi

# 2. ERROR lines since the last run.
since=$now
[[ -f "$STATE/last-run" ]] && since=$(<"$STATE/last-run")
errors=$(journalctl -u sarthi --since "@$since" --no-pager -o cat 2>/dev/null | grep -F 'level=ERROR' | head -5)
if [[ -n "$errors" ]]; then
	alert errors "server errors:
${errors:0:3000}"
fi
echo "$now" >"$STATE/last-run"

# 3. Nightly backup.
if systemctl is-failed --quiet sarthi-backup.service 2>/dev/null; then
	alert backup "nightly backup failed. journalctl -u sarthi-backup -n 30"
fi

# 4. Disk.
used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if ((used > 90)); then
	alert disk "disk ${used}% full"
fi
exit 0
