#!/bin/sh
set -eu

simulator_name="${SMARTISAN_SIMULATOR_NAME:-Codex Smartisan iPhone 16}"
bundle_id="com.jingweipro.SmartisanClockiOS"
derived_data="${TMPDIR:-/tmp}/smartisan-clock-restoration-derived-data"

device_id=$(xcrun simctl list devices | sed -n "s/.*${simulator_name} (\([0-9A-F-]*\)).*/\1/p" | head -1)
if [ -z "$device_id" ]; then
  echo "FAIL: simulator not found: $simulator_name" >&2
  exit 1
fi

xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b >/dev/null

xcodebuild -quiet \
  -project SmartisanClockiOS.xcodeproj \
  -scheme SmartisanClockiOS \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_path="$derived_data/Build/Products/Debug-iphonesimulator/SmartisanClockiOS.app"
test -d "$app_path/PlugIns/SmartisanClockLiveActivity.appex"

xcrun simctl terminate "$device_id" "$bundle_id" 2>/dev/null || true
xcrun simctl install "$device_id" "$app_path"

data_container=$(xcrun simctl get_app_container "$device_id" "$bundle_id" data)
session_path="$data_container/Library/Application Support/SmartisanClock/TimerSession-v1.json"
rm -f "$session_path"

read_session() {
  test -s "$session_path" || return 1
  cat "$session_path"
}

xcrun simctl launch "$device_id" "$bundle_id" \
  -SmartisanScreen timer \
  -SmartisanTimerTestDurationSeconds 90 >/dev/null

first_session=""
attempt=0
while [ "$attempt" -lt 40 ]; do
  if first_session=$(read_session 2>/dev/null); then break; fi
  attempt=$((attempt + 1))
  sleep 0.25
done

if [ -z "$first_session" ]; then
  echo "FAIL: timer session was not persisted; accept the one-time AlarmKit prompt and rerun" >&2
  exit 1
fi

first_id=$(printf '%s' "$first_session" | jq -r '.alarmID')
first_fire_date=$(printf '%s' "$first_session" | jq -r '.fireDate')
test -n "$first_id"
test "$first_id" != "null"

xcrun simctl terminate "$device_id" "$bundle_id"
xcrun simctl launch "$device_id" "$bundle_id" -SmartisanScreen timer >/dev/null

second_session=""
attempt=0
while [ "$attempt" -lt 40 ]; do
  if second_session=$(read_session 2>/dev/null); then break; fi
  attempt=$((attempt + 1))
  sleep 0.25
done

second_id=$(printf '%s' "$second_session" | jq -r '.alarmID')
second_fire_date=$(printf '%s' "$second_session" | jq -r '.fireDate')

if [ "$first_id" != "$second_id" ]; then
  echo "FAIL: timer ID changed after relaunch" >&2
  exit 1
fi

if [ "$first_fire_date" != "$second_fire_date" ]; then
  echo "FAIL: fire date changed after relaunch" >&2
  exit 1
fi

echo "TimerRestorationSimulatorTest passed: $first_id"
