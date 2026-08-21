#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
OUTPUT_DIR=${1:-"$PROJECT_ROOT/dist"}

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

read OUTPUT_UID OUTPUT_MODE <<< "$(stat -f '%u %Lp' "$OUTPUT_DIR")"
if [[ "$OUTPUT_UID" != "$(id -u)" || $(( 8#$OUTPUT_MODE & 8#022 )) -ne 0 ]]; then
  print -u2 "Output directory must be owned by the current user and not writable by group or others: $OUTPUT_DIR"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_ROOT/SmartisanClockiOS/Info.plist" 2>/dev/null || true)

if [[ -z "$VERSION" || "$VERSION" == *'$('* ]]; then
  VERSION=$(xcodebuild -project "$PROJECT_ROOT/SmartisanClockiOS.xcodeproj" \
    -scheme SmartisanClockiOS -configuration Release \
    -destination 'generic/platform=iOS' -showBuildSettings \
    | awk '/MARKETING_VERSION/ {print $3; exit}')
fi

TEMP_ROOT=$(mktemp -d /tmp/SmartisanClockUnsigned.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT

IPA_NAME="SmartisanClock-iOS-v${VERSION}-unsigned.ipa"
CHECKSUM_NAME="$IPA_NAME.sha256"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
CHECKSUM_PATH="$OUTPUT_DIR/$CHECKSUM_NAME"
PRIVATE_IPA_PATH="$TEMP_ROOT/$IPA_NAME"
PRIVATE_CHECKSUM_PATH="$TEMP_ROOT/$CHECKSUM_NAME"

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
  /usr/bin/zip -qry "$PRIVATE_IPA_PATH" Payload
)

(
  cd "$TEMP_ROOT"
  /usr/bin/shasum -a 256 "$IPA_NAME" > "$CHECKSUM_NAME"
)

if [[ -e "$IPA_PATH" || -L "$IPA_PATH" || -e "$CHECKSUM_PATH" || -L "$CHECKSUM_PATH" ]]; then
  print -u2 "Refusing to overwrite an existing artifact: $IPA_PATH"
  exit 1
fi

publish() {
  local source_path=$1 destination_name=$2
  /bin/mv -n "$source_path" "./$destination_name"
  if [[ -e "$source_path" ]]; then
    print -u2 "Refusing to overwrite an existing artifact: $OUTPUT_DIR/$destination_name"
    exit 1
  fi
}

(
  cd "$OUTPUT_DIR"
  read OUTPUT_UID OUTPUT_MODE <<< "$(stat -f '%u %Lp' .)"
  if [[ "$OUTPUT_UID" != "$(id -u)" || $(( 8#$OUTPUT_MODE & 8#022 )) -ne 0 ]]; then
    print -u2 "Output directory changed or became unsafe: $OUTPUT_DIR"
    exit 1
  fi
  publish "$PRIVATE_IPA_PATH" "$IPA_NAME"
  publish "$PRIVATE_CHECKSUM_PATH" "$CHECKSUM_NAME"
)

print "Created: $IPA_PATH"
print "Checksum: $CHECKSUM_PATH"
