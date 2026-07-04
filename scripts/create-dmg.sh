#!/usr/bin/env bash
# create-dmg.sh
#
# Builds, signs, notarizes, and staples a distributable .dmg for InterlinedList.
#
# Consumes: build/export/InterlinedList.app — the already-notarized, stapled
#           .app produced by notarize-and-package.sh.
#
# Distribution model is Developer ID (NOT App Store).
#
# ------------------------------------------------------------------
# Required environment variables (no hardcoded credentials in-script):
#
#   VERSION                     Release version string, e.g. 0.1.0.
#   CODESIGN_IDENTITY           Full common name of the Developer ID
#                               Application identity, e.g.
#                                 "Developer ID Application: Acme Corp (XXXXXXXXXX)"
#   APPLE_ID                    Apple ID email address.
#   APPLE_TEAM_ID               10-character Team ID (e.g. ABCDE12345).
#   NOTARIZATION_PASSWORD       App-specific password for notarytool; generate at
#                               https://appleid.apple.com → App-Specific Passwords.
#
# ------------------------------------------------------------------
# Usage:
#
#   # Prereq: run notarize-and-package.sh first to produce the notarized .app.
#
#   VERSION=0.1.0 \
#   CODESIGN_IDENTITY="Developer ID Application: Acme Corp (ABCDE12345)" \
#   APPLE_ID=you@example.com \
#   APPLE_TEAM_ID=ABCDE12345 \
#   NOTARIZATION_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#       ./scripts/create-dmg.sh
#
# Output:
#   build/InterlinedList-<VERSION>.dmg

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

APP_PATH="$BUILD_DIR/export/InterlinedList.app"
DMG_TEMP="$BUILD_DIR/InterlinedList-rw.dmg"

# ─── Credential guard ────────────────────────────────────────────────────────
: "${VERSION:?VERSION is required (e.g. 0.1.0).}"
: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required (Developer ID Application).}"
: "${APPLE_ID:?APPLE_ID is required.}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required.}"
: "${NOTARIZATION_PASSWORD:?NOTARIZATION_PASSWORD is required.}"

FINAL_DMG="$BUILD_DIR/InterlinedList-${VERSION}.dmg"

echo "==> DMG: InterlinedList-${VERSION}.dmg"

# ─── Pre-flight ───────────────────────────────────────────────────────────────
[[ -d "$APP_PATH" ]] || {
    echo "!! .app not found at $APP_PATH" >&2
    echo "   Run notarize-and-package.sh first to produce the notarized .app." >&2
    exit 1
}

# ─── Step 1: Create read-write staging image ─────────────────────────────────
echo "==> Step 1: Creating read-write staging image"
rm -f "$FINAL_DMG" "$DMG_TEMP"

# Size the image from the actual .app footprint plus 50 MB headroom; floor at
# 150 MB to ensure room for the Applications symlink and HFS+ metadata.
APP_SIZE_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_SIZE_MB=$(( (APP_SIZE_KB / 1024) + 50 ))
DMG_SIZE_MB=$(( DMG_SIZE_MB < 150 ? 150 : DMG_SIZE_MB ))

hdiutil create \
    -volname "InterlinedList" \
    -size "${DMG_SIZE_MB}m" \
    -fs HFS+ \
    -format UDRW \
    "$DMG_TEMP"

# ─── Step 2: Attach, populate, detach ─────────────────────────────────────────
echo "==> Step 2: Copying .app and Applications symlink into DMG"
MOUNT_POINT="$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen \
    | awk '/Apple_HFS/ {print $NF}')"

cp -R "$APP_PATH" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"

hdiutil detach "$MOUNT_POINT"

# ─── Step 3: Convert to compressed read-only DMG ──────────────────────────────
echo "==> Step 3: Converting to compressed read-only DMG"
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG"
rm -f "$DMG_TEMP"

# ─── Step 4: Sign the DMG ─────────────────────────────────────────────────────
echo "==> Step 4: Signing DMG"
codesign \
    --sign "$CODESIGN_IDENTITY" \
    --timestamp \
    --verbose \
    "$FINAL_DMG"
codesign --verify --verbose "$FINAL_DMG"

# ─── Step 5: Notarize the DMG ─────────────────────────────────────────────────
echo "==> Step 5: Submitting DMG to Apple notarization service"
xcrun notarytool submit "$FINAL_DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$NOTARIZATION_PASSWORD" \
    --wait

# ─── Step 6: Staple notarization ticket ──────────────────────────────────────
echo "==> Step 6: Stapling notarization ticket to DMG"
xcrun stapler staple "$FINAL_DMG"

# ─── Step 7: Verify ───────────────────────────────────────────────────────────
echo "==> Step 7: Verifying DMG"
spctl --assess --type install --verbose=2 "$FINAL_DMG"

echo ""
echo "==> Done."
echo ""
echo "    $FINAL_DMG"
