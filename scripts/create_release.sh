#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDKROOT_PATH="${SDKROOT:-$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

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
DMG_PATH="$ROOT_DIR/dist/MetalDuck-1.2.0.dmg"

rm -rf "$ROOT_DIR/dist/"*
rm -rf "$STAGE_DIR" "$DMG_STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_STAGE_DIR"

cp "$PRODUCT_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
if [[ -d "$BUNDLE_DIR" ]]; then
  cp -R "$BUNDLE_DIR" "$RESOURCES_DIR/"
fi
if [[ -f "$ICON_FILE" ]]; then
  echo "Found icon at $ICON_FILE, copying to $RESOURCES_DIR/AppIcon.icns"
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "ICON NOT FOUND AT $ICON_FILE" >&2
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
  <string>1.2.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.2.0</string>
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

# Re-sign the full app bundle after assembling it, so Gatekeeper sees a valid signature.
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# Assemble the DMG stage directory
cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

# Set up the DMG background (SKIPPED - Background removed)
# mkdir -p "$DMG_STAGE_DIR/.background"

# Create a temporary empty DMG to configure layout
TEMP_DMG="${DMG_PATH}.temp.dmg"
MOUNT_DIR=$(mktemp -d /tmp/metaldduck_mount.XXXXXX)

# Robust cleanup on exit
cleanup() {
  echo "Cleaning up..."
  hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
  rm -f "$TEMP_DMG"
  rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

rm -f "$TEMP_DMG" "$DMG_PATH"

echo "Creating temporary DMG..."
hdiutil create -srcfolder "$DMG_STAGE_DIR" -volname "MetalDuck" -fs HFS+ -format UDRW -ov "$TEMP_DMG"

echo "Mounting temporary DMG..."
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -noautoopen

echo "Configuring DMG layout..."
osascript <<APPLESCRIPT
tell application "Finder"
    set theWindow to make new Finder window to (POSIX file "$MOUNT_DIR") as alias
    tell theWindow
        open
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set the bounds to {400, 100, 900, 400} -- 500x300 window
    end tell
    
    tell the icon view options of theWindow
        set icon size to 128
        set arrangement to not arranged
        -- background picture removed
    end tell
    
    set position of item "MetalDuck.app" of theWindow to {160, 150}
    set position of item "Applications" of theWindow to {340, 150}
    
    update item "MetalDuck.app" of theWindow
    update item "Applications" of theWindow
    
    delay 2
    close theWindow
end tell
APPLESCRIPT

echo "Detaching DMG..."
hdiutil detach "$MOUNT_DIR"

echo "Converting to final DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"

echo "Finalizing output..."
rm -rf "$STAGE_DIR" "$DMG_STAGE_DIR"

echo "Release package created: $DMG_PATH"
