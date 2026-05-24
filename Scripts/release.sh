#!/usr/bin/env bash
# Build a Release .app, ad-hoc sign it, and package as a .dmg.
# Usage: Scripts/release.sh [version]
#   version defaults to the current short git tag or "dev"

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo dev)}"
VERSION="${VERSION#v}"

BUILD_DIR="build"
APP_PATH="$BUILD_DIR/Build/Products/Release/ClaudeFuel.app"
DMG_NAME="ClaudeFuel-${VERSION}.dmg"
STAGE_DIR="$BUILD_DIR/dmg-stage"

echo "==> Building ClaudeFuel.app (Release, ad-hoc signed)"
xcodebuild -project ClaudeFuel.xcodeproj \
  -scheme ClaudeFuel \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build | tail -20

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build failed: $APP_PATH not found" >&2
  exit 1
fi

echo "==> Staging .dmg contents"
rm -rf "$STAGE_DIR" "$DMG_NAME"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating $DMG_NAME"
hdiutil create \
  -volname "ClaudeFuel" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_NAME"

rm -rf "$STAGE_DIR"

echo
echo "Done: $DMG_NAME"
echo "Next: gh release create v${VERSION} ${DMG_NAME} --title \"v${VERSION}\" --notes \"...\""
