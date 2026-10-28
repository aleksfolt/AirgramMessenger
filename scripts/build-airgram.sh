#!/bin/sh
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$REPO_DIR/build-airgram}"
cd "$REPO_DIR"

RELEASE_XCCONFIG="Telegram-Mac/Release.xcconfig"
SAVED_XCCONFIG="$(mktemp)"
cp "$RELEASE_XCCONFIG" "$SAVED_XCCONFIG"
trap 'cp "$SAVED_XCCONFIG" "$RELEASE_XCCONFIG"; rm -f "$SAVED_XCCONFIG"' EXIT
cp configurations/AirGram.xcconfig "$RELEASE_XCCONFIG"

if [ ! -f Telegram-Mac/AirGram.secrets.xcconfig ]; then
    echo "warning: Telegram-Mac/AirGram.secrets.xcconfig is missing, the build uses the built-in Telegram API ID" >&2
fi

mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/AirGram.xcarchive"
rm -rf "$ARCHIVE"

xcodebuild archive -workspace Telegram-Mac.xcworkspace \
    -scheme Release \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    CODE_SIGNING_ALLOWED=NO \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) GITHUB"

APP="$OUTPUT_DIR/AirGram.app"
rm -rf "$APP"
ditto "$ARCHIVE/Products/Applications/Telegram.app" "$APP"
rm -rf "$APP/Contents/PlugIns/TelegramShare.appex"

codesign --force --deep --sign - "$APP"
codesign --force --sign - --entitlements Telegram-Mac/AirGram-AdHoc.entitlements "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ZIP="$OUTPUT_DIR/AirGram-$VERSION-$BUILD.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
