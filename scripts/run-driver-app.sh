#!/usr/bin/env bash
#
# run-driver-app.sh — run the driver-facing Flutter app (apps/driver_app) in debug.
#
# Defaults to Chrome. Pass a device id to target something else:
#
#   ./scripts/run-driver-app.sh            # -> chrome
#   ./scripts/run-driver-app.sh macos      # -> desktop (needs full Xcode)
#   ./scripts/run-driver-app.sh <emulator> # e.g. an Android device id
#
# Only one Flutter app can be attached to the MCP server at a time — run the
# user app OR the driver app, not both, when inspecting via the agent.
#
# List available devices with:  flutter devices
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-chrome}"

cd "$REPO_ROOT/apps/driver_app"

echo "📦 Resolving dependencies..."
flutter pub get

echo "🚗 Launching driver_app on '${DEVICE}' (debug)..."
echo "   Watch the console for: 'A Dart VM Service ... is available at: http://127.0.0.1:<PORT>'"
exec flutter run -d "$DEVICE" --debug
