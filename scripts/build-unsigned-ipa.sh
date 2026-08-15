#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
OUTPUT_DIR=${1:-"$PROJECT_ROOT/dist"}

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_ROOT/SmartisanClockiOS/Info.plist" 2>/dev/null || true)

if [[ -z "$VERSION" || "$VERSION" == *'$('* ]]; then
  VERSION=$(xcodebuild -project "$PROJECT_ROOT/SmartisanClockiOS.xcodeproj" \
    -scheme SmartisanClockiOS -configuration Release \
    -destination 'generic/platform=iOS' -showBuildSettings \
    | awk '/MARKETING_VERSION/ {print $3; exit}')
fi

IPA_PATH="$OUTPUT_DIR/SmartisanClock-iOS-v${VERSION}-unsigned.ipa"
CHECKSUM_PATH="$IPA_PATH.sha256"

if [[ -e "$IPA_PATH" || -e "$CHECKSUM_PATH" ]]; then
  print -u2 "Refusing to overwrite an existing artifact: $IPA_PATH"
  exit 1
fi

TEMP_ROOT=$(mktemp -d /tmp/SmartisanClockUnsigned.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

xcodebuild \
  -project "$PROJECT_ROOT/SmartisanClockiOS.xcodeproj" \
  -scheme SmartisanClockiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$TEMP_ROOT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build

APP_PATH="$TEMP_ROOT/DerivedData/Build/Products/Release-iphoneos/SmartisanClockiOS.app"

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "Release app bundle was not produced: $APP_PATH"
  exit 1
fi

if [[ -d "$APP_PATH/_CodeSignature" || -f "$APP_PATH/embedded.mobileprovision" ]]; then
  print -u2 "Build unexpectedly contains signing material; refusing to package it."
  exit 1
fi

mkdir -p "$TEMP_ROOT/Package/Payload"
/usr/bin/ditto "$APP_PATH" "$TEMP_ROOT/Package/Payload/SmartisanClockiOS.app"

(
  cd "$TEMP_ROOT/Package"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

/usr/bin/shasum -a 256 "$IPA_PATH" > "$CHECKSUM_PATH"

print "Created: $IPA_PATH"
print "Checksum: $CHECKSUM_PATH"
