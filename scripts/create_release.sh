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

if [[ ! -f "$PRODUCT_BIN" ]]; then
  echo "Release binary not found: $PRODUCT_BIN" >&2
  exit 1
fi

STAGE_DIR="$ROOT_DIR/dist/MetalDuck-macos-arm64"
ZIP_PATH="$ROOT_DIR/dist/MetalDuck-macos-arm64.zip"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

cp "$PRODUCT_BIN" "$STAGE_DIR/"
if [[ -d "$BUNDLE_DIR" ]]; then
  cp -R "$BUNDLE_DIR" "$STAGE_DIR/"
fi
cp "$ROOT_DIR/README.md" "$STAGE_DIR/"
cp -R "$ROOT_DIR/docs" "$STAGE_DIR/"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/"

rm -f "$ZIP_PATH"
(
  cd "$ROOT_DIR/dist"
  zip -r "$(basename "$ZIP_PATH")" "$(basename "$STAGE_DIR")" >/dev/null
)

echo "Release package created: $ZIP_PATH"
