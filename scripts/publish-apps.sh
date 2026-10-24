#!/usr/bin/env bash
#
# publish-apps.sh — put the latest release APKs on the download page,
# https://apps.mojud.life (served by Caddy on the VPS from /var/www/mojud-apps).
#
#   ./scripts/build-user-app-apk.sh && ./scripts/build-driver-app-apk.sh
#   ./scripts/publish-apps.sh            # render + upload
#   ./scripts/publish-apps.sh --dry-run  # render into scripts/apps-page/dist only
#
# Renders scripts/apps-page/index.template.html with each app's version, size
# and SHA-256, plus a QR code for the page, then rsyncs the page, icons and
# APKs to the server. APK file names carry the version so phones never serve a
# stale cached download.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGE_URL="https://apps.mojud.life/"
REMOTE="vultr:/var/www/mojud-apps/"
SRC="$REPO_ROOT/scripts/apps-page"
DIST="$SRC/dist"

version_of() { grep -m1 '^version:' "$REPO_ROOT/apps/$1/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1; }
size_of() { du -m "$1" | awk '{printf "%d MB", $1}'; }
sha_of() { sha256sum "$1" | cut -d' ' -f1; }

USER_APK_SRC="$REPO_ROOT/scripts/user_app-release.apk"
DRIVER_APK_SRC="$REPO_ROOT/scripts/driver_app-release.apk"
for f in "$USER_APK_SRC" "$DRIVER_APK_SRC"; do
  [ -f "$f" ] || { echo "❌ Missing $f — build it first." >&2; exit 1; }
done

USER_VERSION="$(version_of user_app)"
DRIVER_VERSION="$(version_of driver_app)"
USER_APK="mojud-${USER_VERSION}.apk"
DRIVER_APK="sarthi-driver-${DRIVER_VERSION}.apk"

rm -rf "$DIST" && mkdir -p "$DIST"
cp "$USER_APK_SRC" "$DIST/$USER_APK"
cp "$DRIVER_APK_SRC" "$DIST/$DRIVER_APK"
cp "$REPO_ROOT/apps/user_app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" "$DIST/mojud-icon.png"
cp "$REPO_ROOT/apps/driver_app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" "$DIST/sarthi-driver-icon.png"

QR_SVG="$(qrencode -t SVG -m 1 --foreground=0B2239 -o - "$PAGE_URL" | sed '1{/^<?xml/d}')"

USER_VERSION="$USER_VERSION" DRIVER_VERSION="$DRIVER_VERSION" \
USER_APK="$USER_APK" DRIVER_APK="$DRIVER_APK" \
USER_SIZE="$(size_of "$DIST/$USER_APK")" DRIVER_SIZE="$(size_of "$DIST/$DRIVER_APK")" \
USER_SHA="$(sha_of "$DIST/$USER_APK")" DRIVER_SHA="$(sha_of "$DIST/$DRIVER_APK")" \
UPDATED="$(date '+%-d %b %Y')" QR_SVG="$QR_SVG" \
python3 - "$SRC/index.template.html" "$DIST/index.html" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
html = open(src).read()
for key in ("USER_VERSION", "DRIVER_VERSION", "USER_APK", "DRIVER_APK", "USER_SIZE",
            "DRIVER_SIZE", "USER_SHA", "DRIVER_SHA", "UPDATED", "QR_SVG"):
    html = html.replace("{{" + key + "}}", os.environ[key])
open(dst, "w").write(html)
PY

echo "📄 Rendered $DIST ($USER_APK, $DRIVER_APK)"
if [ "${1:-}" = "--dry-run" ]; then exit 0; fi

rsync -az --delete --chmod=D755,F644 "$DIST/" "$REMOTE"
echo "✅ Published → $PAGE_URL"
