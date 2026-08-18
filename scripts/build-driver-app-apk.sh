#!/usr/bin/env bash
#
# build-driver-app-apk.sh — build a release APK for the driver Flutter app
# (apps/driver_app), pointed at the deployed VPS backend, and copy it into
# scripts/.
#
# Unlike run-driver-app.sh (which targets your local Go server at
# localhost:8080 / 10.0.2.2:8080 for debug), this builds a real distributable
# APK that calls the production API — see ApiConfig in
# apps/driver_app/lib/core/config/api_config.dart.
#
#   ./scripts/build-driver-app-apk.sh          # release APK
#   ./scripts/build-driver-app-apk.sh debug    # debug APK
#
# The VPS domain is read from server/.env.prod (the same file
# setup-vps.sh reads) — not a script argument, so it can't drift from what's
# actually deployed. Copy server/.env.prod.example there and fill in DOMAIN
# if it doesn't exist yet.
#
# Fast2SMS (the OTP provider) is a server-side secret only — it lives in
# server/.env.prod and is read by the Go server, not the app, so there is
# nothing for this script to feed it. Once FAST2SMS_API_KEY/FAST2SMS_OTP_ID
# are set on the VPS (see deploy/README.md), the deployed backend sends real
# SMS OTPs to both /auth/otp (customer) and /driver/auth/otp (driver) — this
# APK gets that for free by pointing at the same DOMAIN as build-user-app-apk.sh.
#
# Release builds are signed with apps/driver_app/android/key.properties if
# present (see build.gradle.kts); otherwise Flutter falls back to the debug
# key, so this still runs on a fresh checkout — just not distributable.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-release}"

PROD_ENV="$REPO_ROOT/server/.env.prod"
DOMAIN=""
if [ -f "$PROD_ENV" ]; then
  DOMAIN="$(grep -E '^DOMAIN=' "$PROD_ENV" | cut -d= -f2-)"
fi

if [ -z "$DOMAIN" ]; then
  echo "❌ No DOMAIN found in server/.env.prod." >&2
  echo "   Copy server/.env.prod.example to server/.env.prod and fill in DOMAIN" >&2
  echo "   with the VPS host from your setup-vps.sh run." >&2
  exit 1
fi

API_BASE_URL="https://$DOMAIN"

cd "$REPO_ROOT/apps/driver_app"

echo "🌐 Pointing APK at ${API_BASE_URL}"

echo "📦 Resolving dependencies..."
flutter pub get

echo "🛠️  Building driver_app APK (${MODE})..."
flutter build apk --"${MODE}" --dart-define="API_BASE_URL=${API_BASE_URL}"

BUILT_APK="build/app/outputs/flutter-apk/app-${MODE}.apk"
if [ ! -f "$BUILT_APK" ]; then
  echo "❌ Expected APK not found at apps/driver_app/${BUILT_APK}" >&2
  exit 1
fi

DEST="$REPO_ROOT/scripts/driver_app-${MODE}.apk"
cp "$BUILT_APK" "$DEST"
echo "✅ APK copied to ${DEST}"
