#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Embercue.app"
ICONSET="$DIST/AppIcon.iconset"
VERSION="${VERSION:-0.1.1}"
BUILD="${BUILD_NUMBER:-1}"
IDENTITY="${SIGN_IDENTITY:--}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z]+)*$ ]]; then
  echo "VERSION must be a numeric marketing version (for example 0.1.0)" >&2
  exit 64
fi
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must contain only decimal digits" >&2
  exit 64
fi
cd "$ROOT"
swift build -c release
BUILD_PATH="$(swift build -c release --show-bin-path)"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
swift "$ROOT/Tools/GenerateAppIcon.swift" "$DIST/icon-png"
for SIZE in 16 32 64 128 256 512 1024; do
  DIMENSIONS="$(sips -g pixelWidth -g pixelHeight "$DIST/icon-png/$SIZE.png" | awk '/pixelWidth:|pixelHeight:/ { print $2 }' | tr '\n' ' ')"
  if [[ "$DIMENSIONS" != "$SIZE $SIZE " ]]; then
    echo "Generated icon $SIZE.png has unexpected dimensions: $DIMENSIONS" >&2
    exit 1
  fi
done
for SIZE in 16 32 128 256 512; do
  cp "$DIST/icon-png/$SIZE.png" "$ICONSET/icon_${SIZE}x${SIZE}.png"
  DOUBLE=$((SIZE * 2))
  cp "$DIST/icon-png/$DOUBLE.png" "$ICONSET/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Licenses/swift-markdown" "$APP/Contents/Resources/Licenses/swift-cmark"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/ThirdParty/swift-markdown/LICENSE.txt" "$APP/Contents/Resources/Licenses/swift-markdown/LICENSE.txt"
cp "$ROOT/ThirdParty/swift-markdown/NOTICE.txt" "$APP/Contents/Resources/Licenses/swift-markdown/NOTICE.txt"
cp "$ROOT/ThirdParty/swift-cmark/COPYING" "$APP/Contents/Resources/Licenses/swift-cmark/COPYING"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
cp "$BUILD_PATH/Embercue" "$APP/Contents/MacOS/Embercue"
codesign --force --sign "$IDENTITY" "$APP"
echo "Packaged $APP with signing identity: $IDENTITY"
