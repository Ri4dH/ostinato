#!/bin/zsh
# Captures App Store screenshots with UITests/ScreenshotTests.swift.
# Usage: scripts/screenshots.sh [output-dir] [device names...]
# Default devices: iPhone 17 Pro Max (6.9"), iPad Pro 13-inch (M5), Apple Watch Ultra 3.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-docs/app-store/screenshots}
(( $# )) && shift
DEVICES=("$@")
(( ${#DEVICES[@]} )) || DEVICES=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)" "Apple Watch Ultra 3 (49mm)")
DERIVED=${DERIVED_DATA:-build/screenshots-derived-data}

udid_for() { # newest iOS runtime that has this device name
  xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
os = 'watchOS' if 'Watch' in sys.argv[1] else 'iOS'
runtimes = sorted((r for r in data if f'.{os}-' in r), key=lambda r: [int(x) for x in r.split(f'{os}-')[1].split('-')], reverse=True)
print(next((d['udid'] for r in runtimes for d in data[r] if d['name'] == sys.argv[1]), ''))" "$1"
}

for device in "${DEVICES[@]}"; do
  udid=$(udid_for "$device")
  [[ -z $udid ]] && { echo "No simulator named $device"; exit 1 }
  xcrun simctl boot $udid 2>/dev/null || true
  xcrun simctl bootstatus $udid -b >/dev/null
  if [[ $device == *Watch* ]]; then
    scheme=OstinatoWatch; tests=OstinatoWatchUITests/WatchScreenshotTests
  else
    scheme=Ostinato; tests=OstinatoUITests/ScreenshotTests
    xcrun simctl ui $udid appearance light
  fi
  xcrun simctl status_bar $udid override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true
  dir="$PWD/$OUT/$device"
  rm -rf "$dir"
  TEST_RUNNER_SCREENSHOT_DIR="$dir" xcodebuild test -quiet -project Ostinato.xcodeproj -scheme $scheme \
    -destination "id=$udid" -derivedDataPath "$DERIVED" \
    -only-testing:$tests 2>&1 | grep -vE "^\s*$" | tail -5
  ls "$dir"
done
