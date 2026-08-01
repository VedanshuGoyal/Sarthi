#!/usr/bin/env bash
#
# build-user-app-apk.sh — build a release APK for the customer Flutter app
# (apps/user_app), pointed at the deployed VPS backend, and copy it into
# scripts/.
#
# Unlike run-user-app.sh (which targets your local Go server at
# localhost:8080 / 10.0.2.2:8080 for debug), this builds a real distributable
# APK that calls the production API — see ApiConfig in
# apps/user_app/lib/core/config/api_config.dart.
#
#   ./scripts/build-user-app-apk.sh          # release APK
#   ./scripts/build-user-app-apk.sh debug    # debug APK
#
# The VPS domain is read from server/.env.prod (the same file
# setup-vps.sh reads) — not a script argument, so it can't drift from what's
# actually deployed. Copy server/.env.prod.example there and fill in DOMAIN
# if it doesn't exist yet.
#
# Release builds are signed with apps/user_app/android/key.properties if
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

cd "$REPO_ROOT/apps/user_app"

# Feed .env (Ola Maps OAuth creds) into the build's compile-time defines when
# present, same as run-user-app.sh — independent of which backend it talks to.
DART_DEFINES=(--dart-define="API_BASE_URL=${API_BASE_URL}")
if [ -f .env ]; then
  DART_DEFINES+=(--dart-define-from-file=.env)
  echo "🔑 Loading Ola Maps credentials from apps/user_app/.env"

  MAPS_KEY="$(grep -E '^MAPS_API_KEY=' .env | cut -d= -f2- || true)"
  printf 'MAPS_API_KEY=%s\n' "${MAPS_KEY}" > ios/Flutter/Maps.xcconfig
  if [ -n "${MAPS_KEY}" ]; then
    echo "🗺️  Google Maps key wired into the native build."
  else
    echo "⚠️  No MAPS_API_KEY in .env — the 'Select on map' step won't load tiles."
  fi
else
  echo "⚠️  No apps/user_app/.env — map search will show 'maps isn't set up'."
  echo "   Copy .env.example to .env and add your Ola Maps + MAPS_API_KEY keys."
fi

echo "🌐 Pointing APK at ${API_BASE_URL}"

echo "📦 Resolving dependencies..."
flutter pub get

echo "🛠️  Building user_app APK (${MODE})..."
flutter build apk --"${MODE}" "${DART_DEFINES[@]}"

BUILT_APK="build/app/outputs/flutter-apk/app-${MODE}.apk"
if [ ! -f "$BUILT_APK" ]; then
  echo "❌ Expected APK not found at apps/user_app/${BUILT_APK}" >&2
  exit 1
fi

DEST="$REPO_ROOT/scripts/user_app-${MODE}.apk"
cp "$BUILT_APK" "$DEST"
echo "✅ APK copied to ${DEST}"
