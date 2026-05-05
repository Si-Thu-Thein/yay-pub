#!/bin/bash
set -euo pipefail

APP_PATH="build/Build/Products/Release/Yay.app"
DMG_NAME="${1:+Yay-${1}.dmg}"
DMG_NAME="${DMG_NAME:-Yay.dmg}"

echo "Building Yay..."

xcodebuild \
  -project Yay.xcodeproj \
  -scheme Yay \
  -configuration Release \
  -derivedDataPath build \
  -arch arm64 \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  build

echo "Creating DMG..."
STAGING_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Yay" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING_DIR"

echo "Done: $DMG_NAME"
