#!/usr/bin/env bash
#
# server-hardening rollout — the box tasks left after the 17 Nov 2026 deploy.
# The OWNER runs it from the laptop:
#
#   bash docs/features/server-hardening-rollout.sh
#
# Steps (stops at the first failure; each one is safe to run again):
#   1. Caddy: 13 MB request-body cap on the API site (KYC uploads), as in
#      server/deploy/Caddyfile. Backed up, validated, reloaded; restored if
#      the new file doesn't validate.
#   2. /etc/sarthi/sarthi.env: SUPPORT_PHONE (the contact number on
#      apps.mojud.life), LATEST_BUILD_USER_APP=9, LATEST_BUILD_DRIVER_APP=8.
#      Restart, wait for /readyz; restored and restarted if it doesn't come up.
#   3. SSH: keys only (no passwords; root by key only). An automatic revert is
#      armed for 3 minutes and cancelled only after a fresh key login from
#      this laptop works, so a mistake can't lock you out. The Vultr web
#      console still works either way.
#   4. Uptime check from outside the box: .github/workflows/uptime.yml asks
#      /readyz every 10 minutes and alerts the MOJUD Build bot on Telegram.
#      This sets its two repo secrets from ~/.config/cgwb-tg.env and runs it
#      once.
set -euo pipefail

SUPPORT_PHONE="${SUPPORT_PHONE:-919425326724}" # digits with country code, for wa.me links
REPO="VedanshuGoyal/Sarthi"
API="https://api.mojud.life"
TG_ENV="$HOME/.config/cgwb-tg.env" # MOJUD Build bot (token + chat id)
STAMP="$(date +%Y%m%d-%H%M%S)"

log() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
[[ "$SUPPORT_PHONE" =~ ^[1-9][0-9]{9,14}$ ]] || die "SUPPORT_PHONE must be digits with country code"

# A fresh connection every time: a shared ControlMaster would hide a broken login.
fresh() { ssh -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=15 vultr "$@"; }

# --- 1. Caddy body limit ------------------------------------------------------
log "Caddy: 13 MB body cap on the API site"
fresh bash -s -- "$STAMP" <<'REMOTE'
set -euo pipefail
F=/etc/caddy/Caddyfile
if grep -q 'max_size 13MB' "$F"; then echo "    already set"; exit 0; fi
B="$F.bak-$1"; cp -p "$F" "$B"
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "{$DOMAIN} {\n\treverse_proxy localhost:8080\n"
new = ("{$DOMAIN} {\n\t# KYC uploads are the largest bodies (12 MiB limit in the server).\n"
       "\trequest_body {\n\t\tmax_size 13MB\n\t}\n\treverse_proxy localhost:8080\n")
if s.count(old) != 1:
    sys.exit("the API site block isn't in the expected shape; edit it by hand")
open(p, "w").write(s.replace(old, new))
PY
set -a; . /etc/sarthi/caddy.env; set +a
if caddy validate --config "$F" --adapter caddyfile >/tmp/caddy-validate.log 2>&1; then
  systemctl reload caddy
  echo "    reloaded (backup $B)"
else
  cp -p "$B" "$F"
  tail -5 /tmp/caddy-validate.log
  echo "    validate failed; the old file is back" >&2
  exit 1
fi
REMOTE
for u in "$API/readyz" https://apps.mojud.life/; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$u")"
  [ "$code" = 200 ] || die "$u → $code after the Caddy reload"
  echo "  ok 200  $u"
done

# --- 2. App settings in sarthi.env --------------------------------------------
log "sarthi.env: SUPPORT_PHONE, LATEST_BUILD_*"
fresh bash -s -- "$STAMP" "$SUPPORT_PHONE" <<'REMOTE'
set -euo pipefail
E=/etc/sarthi/sarthi.env; B="$E.bak-$1"
cp -p "$E" "$B"
set_env() {
  if grep -q "^$1=" "$E"; then sed -i "s|^$1=.*|$1=$2|" "$E"; else printf '%s=%s\n' "$1" "$2" >> "$E"; fi
}
set_env SUPPORT_PHONE "$2"
set_env LATEST_BUILD_USER_APP 9
set_env LATEST_BUILD_DRIVER_APP 8
systemctl restart sarthi
for _ in $(seq 30); do
  curl -fsS localhost:8080/readyz >/dev/null 2>&1 && { echo "    restarted, ready"; exit 0; }
  sleep 1
done
echo "    not ready in 30 s; restoring the old env" >&2
cp -p "$B" "$E"; systemctl restart sarthi
exit 1
REMOTE
curl -fsS --max-time 15 "$API/app/config" | python3 -c '
import json, sys
a = json.load(sys.stdin)["apps"]
assert a["user_app"]["latestBuild"] == 9 and a["driver_app"]["latestBuild"] == 8, a
print("  ok /app/config latest builds 9 / 8")'

# --- 3. SSH keys only -----------------------------------------------------------
log "SSH: keys only (auto-revert armed for 3 minutes)"
fresh bash -s <<'REMOTE'
set -euo pipefail
D=/etc/ssh/sshd_config.d/00-mojud-keys-only.conf
[ -s /root/.ssh/authorized_keys ] || { echo "root has no authorized_keys; not touching SSH" >&2; exit 1; }
cat > "$D" <<'CONF'
# Keys only (docs/features/server-hardening-rollout.sh). sshd keeps the first
# value it reads, so this file beats 50-cloud-init.conf.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
CONF
sshd -t || { rm -f "$D"; echo "sshd -t failed; removed" >&2; exit 1; }
systemctl stop mojud-ssh-revert.timer 2>/dev/null || true
systemd-run --quiet --unit=mojud-ssh-revert --on-active=180 \
  /bin/sh -c "rm -f $D; systemctl reload ssh || systemctl reload sshd"
systemctl reload ssh 2>/dev/null || systemctl reload sshd
sshd -T | grep -E '^(passwordauthentication|permitrootlogin) ' | sed 's/^/    /'
REMOTE
if fresh true; then
  fresh 'systemctl stop mojud-ssh-revert.timer' && echo "  ok fresh key login works; revert cancelled"
else
  die "a fresh key login failed — leave it: the change reverts by itself within 3 minutes"
fi
# Without a key the server must list only "publickey" as a way in.
denied="$(ssh -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password,keyboard-interactive vultr true 2>&1 || true)"
grep -q 'Permission denied' <<<"$denied" || die "unexpected answer without a key: $denied"
if grep -qi 'password' <<<"$denied"; then
  die "the server still offers password login: $denied"
fi
echo "  ok password login refused"

# --- 4. Uptime check from outside -------------------------------------------------
log "Uptime check (GitHub Actions)"
[ -r "$TG_ENV" ] || die "no $TG_ENV for the alert bot"
( set -a; . "$TG_ENV"; set +a
  printf '%s' "${TG_TOKEN:?}" | gh secret set MOJUD_TG_TOKEN --repo "$REPO"
  printf '%s' "${TG_CHAT:?}" | gh secret set MOJUD_TG_CHAT --repo "$REPO" )
gh workflow run uptime.yml --repo "$REPO"
echo "  started a first run: gh run list --repo $REPO --workflow uptime.yml"

log "Done"
