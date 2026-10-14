#!/bin/sh
# Captures the store screenshots, then composes the publishing sets with
# tool/store_screenshots.py: the raw captures land in build/screenshots/raw/,
# and only the publishing sets reach publish/screenshots/ (git-ignored).
#
#   sh tool/store_screenshots.sh [ios|ios-dark|android|all]
#   EP_COMPOSE=0 sh tool/store_screenshots.sh ...   (captures only)
#
# Everything runs against the local fake API (tool/fake_cf_api, synthetic
# demo data only): the script starts it, and stops it when it ends. Nothing
# reaches Cloudflare.
#
# iOS: the iPhone 6.9" (iPhone 16 Pro Max, 1320x2868) and iPad 13" (iPad Pro
# 13-inch (M4), 2064x2752) simulators, from the newest runtime that has them.
# EP_IPHONE and EP_IPAD name others of the same sizes. The iPhone is also
# shot in the app's dark appearance, for the website's dark mode only. Both are shot in
# portrait: iPadOS ignores an app's orientation request while the app
# supports multitasking. The captures hold the app's window only, so the
# status bar is never in them.
#
# Android: the first running emulator (start one first). Its display is
# resized for each capture: 1080x1920 at 420 dpi for the phone, then
# 1440x2560 at 320 dpi for the tablet, both portrait. The size and density
# are ALWAYS reset afterwards, including when a capture fails.
set -eu
cd "$(dirname "$0")/.."

IPHONE=${EP_IPHONE:-iPhone 16 Pro Max}
IPAD=${EP_IPAD:-iPad Pro 13-inch (M4)}
PORT=8789

drive() { # <device id> <folder> <host the device reaches this Mac at> [appearance]
  flutter drive --driver=test_driver/store_screenshots.dart \
    --target=integration_test/store_screenshots_test.dart -d "$1" \
    --dart-define=SHOT_DEVICE="$2" --dart-define=SHOT_APPEARANCE="${4:-light}" \
    --dart-define=CF_API_BASE="http://$3:$PORT/client/v4" \
    --dart-define=MAIL_WORKER_URL="http://$3:$PORT"
}

# The fake API, unless one is already listening.
fake_api() {
  if curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
    return
  fi
  dart run tool/fake_cf_api/server.dart &
  FAKE_PID=$!
  i=0
  until curl -s -o /dev/null "http://127.0.0.1:$PORT/"; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
      echo "the fake API did not start on port $PORT" >&2
      exit 1
    fi
    sleep 1
  done
}

FAKE_PID=
ADB=
SERIAL=
cleanup() {
  if [ -n "$SERIAL" ]; then
    "$ADB" -s "$SERIAL" shell wm size reset || true
    "$ADB" -s "$SERIAL" shell wm density reset || true
  fi
  if [ -n "$FAKE_PID" ]; then
    kill "$FAKE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# The udid of the simulator called $1 on the newest runtime that has one.
sim_id() {
  xcrun simctl list devices available | awk -v name="$1" '
    index($0, "    " name " (") == 1 {
      match($0, /\([0-9A-F-]+\)/)
      id = substr($0, RSTART + 1, RLENGTH - 2)
    }
    END { print id }'
}

ios_device() { # <simulator name> <folder> [appearance]
  id=$(sim_id "$1")
  if [ -z "$id" ]; then
    echo "no available simulator named \"$1\"" >&2
    exit 1
  fi
  xcrun simctl boot "$id" 2>/dev/null || true
  xcrun simctl bootstatus "$id" -b >/dev/null
  drive "$id" "$2" 127.0.0.1 "${3:-light}"
}

ios() {
  ios_device "$IPHONE" iphone-6.9
  ios_device "$IPAD" ipad-13
  ios_dark
}

# The website's dark-mode tour (not a store set).
ios_dark() {
  ios_device "$IPHONE" iphone-6.9-dark dark
}

# adb from the PATH, or from the Android SDK: ANDROID_HOME, ANDROID_SDK_ROOT,
# then the SDK's default location on a Mac. It is often not on the PATH.
find_adb() {
  if command -v adb >/dev/null 2>&1; then
    echo adb
    return
  fi
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
    if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then
      echo "$sdk/platform-tools/adb"
      return
    fi
  done
}

android() {
  ADB=$(find_adb)
  if [ -z "$ADB" ]; then
    echo "adb not found: put the SDK's platform-tools on the PATH or set ANDROID_HOME" >&2
    exit 1
  fi
  serial=$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')
  if [ -z "$serial" ]; then
    echo "start an Android emulator first" >&2
    exit 1
  fi
  SERIAL=$serial
  "$ADB" -s "$SERIAL" shell wm size 1080x1920
  "$ADB" -s "$SERIAL" shell wm density 420
  drive "$SERIAL" android-phone 10.0.2.2
  "$ADB" -s "$SERIAL" shell wm size 1440x2560
  "$ADB" -s "$SERIAL" shell wm density 320
  drive "$SERIAL" android-tablet 10.0.2.2
}

case "${1:-all}" in
  ios) fake_api; ios ;;
  ios-dark) fake_api; ios_dark ;;
  android) fake_api; android ;;
  all) fake_api; ios; android ;;
  *) echo "usage: sh tool/store_screenshots.sh [ios|ios-dark|android|all]" >&2; exit 2 ;;
esac

# EP_COMPOSE=0 keeps the raw captures only.
if [ "${EP_COMPOSE:-1}" = 1 ] && [ "${1:-all}" != ios-dark ]; then
  python3 tool/store_screenshots.py "${1:-all}"
fi
