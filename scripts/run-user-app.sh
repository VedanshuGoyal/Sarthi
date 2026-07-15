#!/usr/bin/env bash
#
# run-user-app.sh — run the customer-facing Flutter app (apps/user_app) in debug.
#
# Defaults to Chrome (the easiest MCP-friendly target per SETUP.md). Pass a
# device id to target something else:
#
#   ./scripts/run-user-app.sh              # -> chrome
#   ./scripts/run-user-app.sh macos        # -> desktop (needs full Xcode)
#   ./scripts/run-user-app.sh <emulator>   # e.g. an Android device id
#
# Ola Maps credentials (for the pickup-location step) load from a git-ignored
# apps/user_app/.env via --dart-define-from-file — copy .env.example to .env and
# fill it in. Without it the app still runs; map search shows "maps isn't set up".
#
# List available devices with:  flutter devices
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-chrome}"

cd "$REPO_ROOT/apps/user_app"

# Feed .env (Ola Maps OAuth creds) into the app's compile-time defines when
# present. --dart-define-from-file maps each KEY=VALUE onto String.fromEnvironment.
DART_DEFINES=()
if [ -f .env ]; then
  DART_DEFINES+=(--dart-define-from-file=.env)
  echo "🔑 Loading Ola Maps credentials from apps/user_app/.env"
else
  echo "⚠️  No apps/user_app/.env — map search will show 'maps isn't set up'."
  echo "   Copy .env.example to .env and add your Ola Maps credentials."
fi

echo "📦 Resolving dependencies..."
flutter pub get

echo "📱 Launching user_app on '${DEVICE}' (debug)..."
echo "   Watch the console for: 'A Dart VM Service ... is available at: http://127.0.0.1:<PORT>'"
echo "   (that PORT feeds the flutter-mcp-toolkit config — see SETUP.md)"
exec flutter run -d "$DEVICE" --debug ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}
