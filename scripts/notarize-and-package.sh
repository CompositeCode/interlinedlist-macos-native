#!/usr/bin/env bash
# notarize-and-package.sh
#
# End-to-end release pipeline for InterlinedList (M7 ship path):
#
#   archive → export (Developer ID) → verify sign → notarize → staple →
#   pkgbuild (component) → productbuild (signed distribution) → verify pkg
#
# Distribution model is Developer ID (NOT App Store). Output is a signed,
# notarized `.pkg` installer suitable for direct download / Sparkle delta
# publication.
#
# ------------------------------------------------------------------
# Required environment variables (no hardcoded credentials in-script):
#
#   APPLE_ID                    Apple ID email address.
#   APPLE_TEAM_ID               10-character Team ID (e.g. ABCDE12345).
#   CODESIGN_IDENTITY           Full common name of the Developer ID
#                               Application identity in the keychain, e.g.
#                                 "Developer ID Application: Acme Corp (XXXXXXXXXX)"
#   INSTALLER_IDENTITY          Full common name of the Developer ID
#                               Installer identity in the keychain, e.g.
#                                 "Developer ID Installer: Acme Corp (XXXXXXXXXX)"
#
# Optional environment variables:
#
#   NOTARIZATION_KEYCHAIN_PROFILE   Name of the keychain credential profile
#                                   created by scripts/store-notarization-profile.sh.
#                                   Default: NotarizationProfile
#   NOTARIZATION_PASSWORD           Fallback app-specific password. Only used
#                                   if the keychain profile is missing.
#                                   Prefer the keychain profile.
#   APP_VERSION                     Version string embedded in the .pkg
#                                   (informational; the .app's own
#                                   CFBundleShortVersionString is authoritative).
#                                   Default: read from Info.plist.
#
# ------------------------------------------------------------------
# Usage:
#
#   # Prereq (once per machine):
#   APPLE_ID=... APPLE_TEAM_ID=... NOTARIZATION_PASSWORD=... \
#       ./scripts/store-notarization-profile.sh
#
#   # Then, for each release:
#   APPLE_ID=you@example.com \
#   APPLE_TEAM_ID=ABCDE12345 \
#   CODESIGN_IDENTITY="Developer ID Application: Acme Corp (ABCDE12345)" \
#   INSTALLER_IDENTITY="Developer ID Installer: Acme Corp (ABCDE12345)" \
#       ./scripts/notarize-and-package.sh
#
# Outputs (all under build/):
#   build/InterlinedList.xcarchive
#   build/export/InterlinedList.app        (signed, stapled)
#   build/InterlinedList.zip               (notarization submission blob)
#   build/InterlinedList-component.pkg     (intermediate — deleted on success)
#   build/InterlinedList.pkg               (final signed distribution)

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

PROJECT="$ROOT_DIR/InterlinedList.xcodeproj"
SCHEME="InterlinedList"
CONFIGURATION="Release"
BUNDLE_ID="com.interlinedlist.macos"
PKG_IDENTIFIER="com.interlinedlist.macos.pkg"

ARCHIVE_PATH="$BUILD_DIR/InterlinedList.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/InterlinedList.app"
ZIP_PATH="$BUILD_DIR/InterlinedList.zip"
COMPONENT_PKG="$BUILD_DIR/InterlinedList-component.pkg"
FINAL_PKG="$BUILD_DIR/InterlinedList.pkg"

EXPORT_OPTIONS_TEMPLATE="$SCRIPT_DIR/ExportOptions.plist"
EXPORT_OPTIONS_RENDERED="$BUILD_DIR/ExportOptions.plist"

NOTARIZATION_KEYCHAIN_PROFILE="${NOTARIZATION_KEYCHAIN_PROFILE:-NotarizationProfile}"

# ─── Usage / credential guard ────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage:
  APPLE_ID=<email> \\
  APPLE_TEAM_ID=<10-char team> \\
  CODESIGN_IDENTITY="Developer ID Application: <Team Name> (<TEAM_ID>)" \\
  INSTALLER_IDENTITY="Developer ID Installer: <Team Name> (<TEAM_ID>)" \\
  [NOTARIZATION_KEYCHAIN_PROFILE=NotarizationProfile] \\
  [NOTARIZATION_PASSWORD=<app-specific pw>] \\
  [APP_VERSION=1.2.3] \\
      $(basename "$0")

Notarization credentials should be stored in the keychain via
scripts/store-notarization-profile.sh (run once). Fall back to
NOTARIZATION_PASSWORD only if the keychain profile is missing.
EOF
}

: "${APPLE_ID:?APPLE_ID is required. $(usage)}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required. $(usage)}"
: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required (Developer ID Application). $(usage)}"
: "${INSTALLER_IDENTITY:?INSTALLER_IDENTITY is required (Developer ID Installer). $(usage)}"

# ─── Clean build dir ─────────────────────────────────────────────────────────
echo "==> Step 0: Preparing clean build directory at $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Step 1: Archive ─────────────────────────────────────────────────────────
echo "==> Step 1: Archiving $SCHEME ($CONFIGURATION)"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY"

# ─── Step 2: Render ExportOptions.plist, then export ─────────────────────────
echo "==> Step 2: Exporting Developer ID .app from archive"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

cp "$EXPORT_OPTIONS_TEMPLATE" "$EXPORT_OPTIONS_RENDERED"
/usr/libexec/PlistBuddy \
    -c "Set :teamID $APPLE_TEAM_ID" \
    "$EXPORT_OPTIONS_RENDERED"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_RENDERED"

if [[ ! -d "$APP_PATH" ]]; then
    echo "!! Export did not produce $APP_PATH — aborting."
    exit 1
fi

# ─── Step 3: Verify code signature ───────────────────────────────────────────
echo "==> Step 3: Verifying code signature on $APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type exec -vvv "$APP_PATH" || {
    echo "!! spctl assessment failed before notarization is expected — inspect above."
    echo "   (This can be acceptable pre-staple; will re-check after stapling.)"
}

# ─── Step 4: Zip for notarization submission ─────────────────────────────────
echo "==> Step 4: Zipping .app for notarization submission"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ─── Step 5: Submit for notarization ─────────────────────────────────────────
echo "==> Step 5: Submitting to Apple notarization service (keychain profile: $NOTARIZATION_KEYCHAIN_PROFILE)"
if security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARIZATION_KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARIZATION_KEYCHAIN_PROFILE" \
        --wait
else
    echo "   (Keychain profile '$NOTARIZATION_KEYCHAIN_PROFILE' not found — falling back to inline credentials.)"
    : "${NOTARIZATION_PASSWORD:?Neither keychain profile '$NOTARIZATION_KEYCHAIN_PROFILE' nor NOTARIZATION_PASSWORD is available. Run scripts/store-notarization-profile.sh once.}"
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$NOTARIZATION_PASSWORD" \
        --wait
fi

# ─── Step 6: Staple ─────────────────────────────────────────────────────────
echo "==> Step 6: Stapling notarization ticket to $APP_PATH"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type exec -vvv "$APP_PATH"

# ─── Step 7: Build component + distribution packages ─────────────────────────
echo "==> Step 7: Building .pkg installer"
rm -f "$COMPONENT_PKG" "$FINAL_PKG"

# Determine version — prefer explicit env, else read from Info.plist.
if [[ -z "${APP_VERSION:-}" ]]; then
    INFO_PLIST_IN_APP="$APP_PATH/Contents/Info.plist"
    APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST_IN_APP")"
fi
echo "   App version: $APP_VERSION"

pkgbuild \
    --component "$APP_PATH" \
    --install-location /Applications \
    --identifier "$PKG_IDENTIFIER" \
    --version "$APP_VERSION" \
    "$COMPONENT_PKG"

productbuild \
    --package "$COMPONENT_PKG" \
    --version "$APP_VERSION" \
    --sign "$INSTALLER_IDENTITY" \
    "$FINAL_PKG"

rm -f "$COMPONENT_PKG"

# ─── Step 8: Verify final pkg ────────────────────────────────────────────────
echo "==> Step 8: Verifying signed .pkg"
pkgutil --check-signature "$FINAL_PKG"
spctl --assess --type install -vvv "$FINAL_PKG"

echo ""
echo "==> Done — ready to publish."
echo "    Notarized .app: $APP_PATH"
echo "    Signed  .pkg  : $FINAL_PKG"
echo ""
echo "    Next: upload $FINAL_PKG, then update the Sparkle appcast."
