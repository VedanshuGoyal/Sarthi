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
# Release builds are signed with apps/driver_app/android/key.properties (see
# build.gradle.kts). Without it a release build fails, because a debug-signed
# APK can't update the installs already out there. ALLOW_DEBUG_SIGNING=1
# builds a local, non-distributable release with the debug key instead.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-release}"

# Check the signing key up front rather than after a long Gradle run.
if [ "$MODE" = "release" ] && [ ! -f "$REPO_ROOT/apps/driver_app/android/key.properties" ]; then
  if [ "${ALLOW_DEBUG_SIGNING:-}" = "1" ]; then
    echo "⚠️  No apps/driver_app/android/key.properties — signing with the debug key." >&2
    echo "   This APK can't update a published install. Don't publish it." >&2
  else
    echo "❌ No apps/driver_app/android/key.properties, so this release can't be signed" >&2
    echo "   with the release key. Restore it, or set ALLOW_DEBUG_SIGNING=1 for a" >&2
    echo "   local, non-distributable build." >&2
    exit 1
  fi
fi

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

# The build number (the +N of pubspec's version) rides on every request as
# X-Build, for the server's minimum-build gate (server/README.md, "App builds").
APP_BUILD="$(sed -nE 's/^version:[[:space:]]*[^+[:space:]]+\+([0-9]+)[[:space:]]*$/\1/p' pubspec.yaml)"
if [ -z "$APP_BUILD" ]; then
  echo "❌ Couldn't read the +N build number from apps/driver_app/pubspec.yaml's version." >&2
  exit 1
fi

BUILD_ARGS=(--dart-define="API_BASE_URL=${API_BASE_URL}" --dart-define="APP_BUILD=${APP_BUILD}")
if [ "${ALLOW_DEBUG_SIGNING:-}" = "1" ]; then
  BUILD_ARGS+=(--android-project-arg=allowDebugSigning=true)
fi

echo "🌐 Pointing APK at ${API_BASE_URL} (build ${APP_BUILD})"

echo "📦 Resolving dependencies..."
flutter pub get

echo "🛠️  Building driver_app APK (${MODE})..."
flutter build apk --"${MODE}" "${BUILD_ARGS[@]}"

BUILT_APK="build/app/outputs/flutter-apk/app-${MODE}.apk"
if [ ! -f "$BUILT_APK" ]; then
  echo "❌ Expected APK not found at apps/driver_app/${BUILT_APK}" >&2
  exit 1
fi

DEST="$REPO_ROOT/scripts/driver_app-${MODE}.apk"
cp "$BUILT_APK" "$DEST"
echo "✅ APK copied to ${DEST}"
