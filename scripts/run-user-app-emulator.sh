#!/usr/bin/env bash
#
# run-user-app-emulator.sh — boot the Android emulator and run user_app on it.
#
# Launches the "Medium_Phone" AVD (see `flutter emulators`) if it isn't
# already booted, waits for it to come fully online, then hands off to
# run-user-app.sh targeting that device.
#
#   ./scripts/run-user-app-emulator.sh              # -> Medium_Phone
#   ./scripts/run-user-app-emulator.sh Pixel_9      # -> a different AVD id
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMULATOR_ID="${1:-Medium_Phone}"

# `adb` lives in the Android SDK's platform-tools, which isn't always on PATH
# (e.g. non-interactive shells). Fall back to the default SDK location.
if ! command -v adb >/dev/null 2>&1; then
  SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
  if [ -x "$SDK_ROOT/platform-tools/adb" ]; then
    export PATH="$SDK_ROOT/platform-tools:$PATH"
  fi
fi

if adb devices | grep -q "^emulator-.*device$"; then
  echo "📱 An Android emulator is already running."
else
  echo "🚀 Booting emulator '${EMULATOR_ID}'..."
  flutter emulators --launch "$EMULATOR_ID"

  echo "⏳ Waiting for the device to attach to adb..."
  adb wait-for-device

  echo "⏳ Waiting for Android to finish booting..."
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2
  done
fi

DEVICE_ID="$(adb devices | awk '/^emulator-.*device$/ {print $1; exit}')"
if [ -z "$DEVICE_ID" ]; then
  echo "❌ No booted Android emulator found." >&2
  exit 1
fi

echo "✅ Emulator ready: ${DEVICE_ID}"
exec "$REPO_ROOT/scripts/run-user-app.sh" "$DEVICE_ID"
