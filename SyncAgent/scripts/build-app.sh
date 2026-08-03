#!/usr/bin/env bash
# Assemble InterlinedListSync.app from the SwiftPM executable, then optionally
# codesign it. Designed to be embedded into InterlinedList.app/Contents/Library/
# LoginItems by the main packaging pipeline, or run standalone for local testing.
#
# Usage:
#   bash scripts/build-app.sh                 # unsigned local build
#   APPLE_DEVELOPER_ID_APPLICATION="Developer ID Application: … (BJA9558E4B)" \
#     bash scripts/build-app.sh               # signed build (hardened runtime)
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PKG_DIR"

CONFIG="${CONFIG:-release}"
BUILD_DIR="${BUILD_DIR:-$PKG_DIR/build}"
APP_NAME="InterlinedListSync"
APP="$BUILD_DIR/$APP_NAME.app"
BIN_NAME="InterlinedListSync"

echo "==> swift build -c $CONFIG"
# Prefer a universal binary; fall back to host arch. Query the bin path with the
# SAME flags used for the build so a universal build resolves to its own output
# directory (not the host-arch one).
if swift build -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null; then
  BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIG"
  BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp "$PKG_DIR/Info.plist" "$APP/Contents/Info.plist"
# Menu-bar icon(s) if present.
if [ -d "$PKG_DIR/Resources" ]; then
  cp -R "$PKG_DIR/Resources/." "$APP/Contents/Resources/" 2>/dev/null || true
fi

# Copy any SwiftPM-generated resource bundles alongside the binary.
for bundle in "$BIN_PATH"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/" || true
done

if [ -n "${APPLE_DEVELOPER_ID_APPLICATION:-}" ]; then
  echo "==> codesigning with: $APPLE_DEVELOPER_ID_APPLICATION"
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG_DIR/InterlinedListSync.entitlements" \
    --sign "$APPLE_DEVELOPER_ID_APPLICATION" \
    "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "==> skipping codesign (APPLE_DEVELOPER_ID_APPLICATION not set); ad-hoc signing"
  codesign --force --sign - \
    --entitlements "$PKG_DIR/InterlinedListSync.entitlements" \
    "$APP" || true
fi

echo "==> built $APP"
