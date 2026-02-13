#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDKROOT_PATH="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"

cd "$ROOT_DIR"

if [[ ! -d "$SDKROOT_PATH" ]]; then
  echo "SDK not found at: $SDKROOT_PATH" >&2
  exit 1
fi

echo "Building release binary..."
SDKROOT="$SDKROOT_PATH" swift build -c release

BIN_DIR="$ROOT_DIR/.build/release"
PRODUCT_BIN="$BIN_DIR/MetalDuck"
BUNDLE_DIR="$BIN_DIR/MetalDuck_MetalDuck.bundle"
ICON_FILE="$ROOT_DIR/Sources/MetalDuck/Assets/AppIcon.icns"

if [[ ! -f "$PRODUCT_BIN" ]]; then
  echo "Release binary not found: $PRODUCT_BIN" >&2
  exit 1
fi

APP_NAME="MetalDuck"
APP_BUNDLE_NAME="${APP_NAME}.app"
STAGE_DIR="$ROOT_DIR/dist/MetalDuck-macos-arm64"
DMG_STAGE_DIR="$ROOT_DIR/dist/MetalDuck-dmg-root"
APP_DIR="$STAGE_DIR/$APP_BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$ROOT_DIR/dist/MetalDuck-macos-arm64.dmg"

rm -rf "$STAGE_DIR" "$DMG_STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGE_DIR"

cp "$PRODUCT_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
if [[ -d "$BUNDLE_DIR" ]]; then
  cp -R "$BUNDLE_DIR" "$RESOURCES_DIR/"
fi
if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>MetalDuck</string>
  <key>CFBundleDisplayName</key>
  <string>MetalDuck</string>
  <key>CFBundleIdentifier</key>
  <string>com.nycolazs.metaldduck</string>
  <key>CFBundleVersion</key>
  <string>0.1.1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.1</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>MetalDuck</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

touch "$CONTENTS_DIR/PkgInfo"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "MetalDuck" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Release package created: $DMG_PATH"
