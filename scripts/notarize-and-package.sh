#!/usr/bin/env bash
# notarize-and-package.sh
#
# End-to-end release pipeline for InterlinedList (M7 ship path):
#
#   archive → export (.app) → verify → notarize .app → staple .app →
#   pkgbuild/productbuild (.pkg) → notarize .pkg → staple .pkg →
#   hdiutil (.dmg) → notarize .dmg → staple .dmg →
#   sha256 checksums → copy artifacts to releases/
#
# Distribution model is Developer ID (NOT App Store).
#
# ------------------------------------------------------------------
# Required environment variables (no hardcoded credentials in-script):
#
#   APPLE_ID                    Apple ID email address.
#   APPLE_TEAM_ID               10-character Team ID (e.g. ABCDE12345).
#   CODESIGN_IDENTITY           Full common name of the Developer ID
#                               Application identity, e.g.
#                                 "Developer ID Application: Acme Corp (XXXXXXXXXX)"
#   INSTALLER_IDENTITY          Full common name of the Developer ID
#                               Installer identity, e.g.
#                                 "Developer ID Installer: Acme Corp (XXXXXXXXXX)"
#
# Optional environment variables:
#
#   NOTARIZATION_KEYCHAIN_PROFILE   Keychain credential profile from
#                                   store-notarization-profile.sh.
#                                   Default: NotarizationProfile
#   NOTARIZATION_PASSWORD           Fallback app-specific password when the
#                                   keychain profile is absent.
#   APP_VERSION                     Override CFBundleShortVersionString read
#                                   from Info.plist (e.g. 0.0.1).
#   RELEASE_LABEL                   Optional suffix appended to filenames only
#                                   (not to the pkg version). E.g. "alpha"
#                                   produces InterlinedList-0.0.1-alpha.pkg.
#
# ------------------------------------------------------------------
# Usage:
#
#   # Prereq (once per machine):
#   APPLE_ID=... APPLE_TEAM_ID=... NOTARIZATION_PASSWORD=... \
#       ./scripts/store-notarization-profile.sh
#
#   # Alpha release:
#   APPLE_ID=you@example.com \
#   APPLE_TEAM_ID=ABCDE12345 \
#   CODESIGN_IDENTITY="Developer ID Application: Acme Corp (ABCDE12345)" \
#   INSTALLER_IDENTITY="Developer ID Installer: Acme Corp (ABCDE12345)" \
#   RELEASE_LABEL=alpha \
#       ./scripts/notarize-and-package.sh
#
#   # Stable release (no label):
#   APPLE_ID=... APPLE_TEAM_ID=... CODESIGN_IDENTITY=... INSTALLER_IDENTITY=... \
#       ./scripts/notarize-and-package.sh
#
# Outputs (copied to releases/ after build):
#   releases/InterlinedList-<version>[-<label>].pkg
#   releases/InterlinedList-<version>[-<label>].pkg.sha256
#   releases/InterlinedList-<version>[-<label>].dmg
#   releases/InterlinedList-<version>[-<label>].dmg.sha256

set -euo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
RELEASES_DIR="$ROOT_DIR/releases"

PROJECT="$ROOT_DIR/InterlinedList.xcodeproj"
SCHEME="InterlinedList"
CONFIGURATION="Release"
PKG_IDENTIFIER="com.interlinedlist.macos.pkg"

EXPORT_OPTIONS_TEMPLATE="$SCRIPT_DIR/ExportOptions.plist"
EXPORT_OPTIONS_RENDERED="$BUILD_DIR/ExportOptions.plist"

NOTARIZATION_KEYCHAIN_PROFILE="${NOTARIZATION_KEYCHAIN_PROFILE:-NotarizationProfile}"
RELEASE_LABEL="${RELEASE_LABEL:-}"

# ─── Usage / credential guard ────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage:
  APPLE_ID=<email> \\
  APPLE_TEAM_ID=<10-char team> \\
  CODESIGN_IDENTITY="Developer ID Application: <Team> (<ID>)" \\
  INSTALLER_IDENTITY="Developer ID Installer: <Team> (<ID>)" \\
  [RELEASE_LABEL=alpha] \\
  [NOTARIZATION_KEYCHAIN_PROFILE=NotarizationProfile] \\
  [NOTARIZATION_PASSWORD=<app-specific pw>] \\
  [APP_VERSION=0.0.1] \\
      $(basename "$0")
EOF
}

: "${APPLE_ID:?APPLE_ID is required. $(usage)}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required. $(usage)}"
: "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required (Developer ID Application). $(usage)}"
: "${INSTALLER_IDENTITY:?INSTALLER_IDENTITY is required (Developer ID Installer). $(usage)}"

# ─── Version + artifact names ────────────────────────────────────────────────
if [[ -z "${APP_VERSION:-}" ]]; then
    APP_VERSION="$(/usr/libexec/PlistBuddy \
        -c 'Print :CFBundleShortVersionString' \
        "$ROOT_DIR/App/Resources/Info.plist")"
fi

if [[ -n "$RELEASE_LABEL" ]]; then
    VERSIONED_NAME="InterlinedList-${APP_VERSION}-${RELEASE_LABEL}"
else
    VERSIONED_NAME="InterlinedList-${APP_VERSION}"
fi

ARCHIVE_PATH="$BUILD_DIR/InterlinedList.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/InterlinedList.app"
APP_ZIP_PATH="$BUILD_DIR/InterlinedList-app.zip"
COMPONENT_PKG="$BUILD_DIR/InterlinedList-component.pkg"
FINAL_PKG="$BUILD_DIR/${VERSIONED_NAME}.pkg"
FINAL_DMG="$BUILD_DIR/${VERSIONED_NAME}.dmg"
DMG_TEMP="$BUILD_DIR/InterlinedList-rw.dmg"

echo "==> Release: $VERSIONED_NAME (pkg version: $APP_VERSION)"

# ─── Step 0: Clean build dir ─────────────────────────────────────────────────
echo "==> Step 0: Preparing clean build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── Step 1: Archive ─────────────────────────────────────────────────────────
echo "==> Step 1: Archiving $SCHEME ($CONFIGURATION)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY"

# ─── Step 2: Export .app ─────────────────────────────────────────────────────
echo "==> Step 2: Exporting Developer ID .app"
mkdir -p "$EXPORT_DIR"
cp "$EXPORT_OPTIONS_TEMPLATE" "$EXPORT_OPTIONS_RENDERED"
/usr/libexec/PlistBuddy \
    -c "Set :teamID $APPLE_TEAM_ID" \
    "$EXPORT_OPTIONS_RENDERED"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_RENDERED"

[[ -d "$APP_PATH" ]] || { echo "!! Export did not produce $APP_PATH"; exit 1; }

# ─── Step 3: Verify .app signature ───────────────────────────────────────────
echo "==> Step 3: Verifying .app code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# ─── Step 4: Notarize the .app ───────────────────────────────────────────────
echo "==> Step 4: Zipping .app for notarization"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"

echo "==> Step 5: Submitting .app to Apple notarization service"
_notarize() {
    local file="$1"
    if security find-generic-password -s "com.apple.gke.notary.tool" \
            -a "$NOTARIZATION_KEYCHAIN_PROFILE" >/dev/null 2>&1; then
        xcrun notarytool submit "$file" \
            --keychain-profile "$NOTARIZATION_KEYCHAIN_PROFILE" \
            --wait
    else
        echo "   (Keychain profile not found — using inline credentials)"
        : "${NOTARIZATION_PASSWORD:?Neither keychain profile nor NOTARIZATION_PASSWORD available.}"
        xcrun notarytool submit "$file" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$NOTARIZATION_PASSWORD" \
            --wait
    fi
}
_notarize "$APP_ZIP_PATH"

echo "==> Step 6: Stapling notarization ticket to .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type exec -vvv "$APP_PATH"

# ─── Step 7: Build signed .pkg ───────────────────────────────────────────────
echo "==> Step 7: Building signed .pkg installer"
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

# ─── Step 8: Notarize + staple the .pkg ──────────────────────────────────────
echo "==> Step 8: Notarizing signed .pkg"
_notarize "$FINAL_PKG"
echo "==> Step 8b: Stapling .pkg"
xcrun stapler staple "$FINAL_PKG"
pkgutil --check-signature "$FINAL_PKG"
spctl --assess --type install -vvv "$FINAL_PKG"

# ─── Step 9: Build .dmg ──────────────────────────────────────────────────────
echo "==> Step 9: Building .dmg disk image"
rm -f "$FINAL_DMG" "$DMG_TEMP"

# Read-write staging DMG
hdiutil create \
    -volname "InterlinedList" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

# Add Applications symlink for drag-to-install
MOUNT_POINT="$(hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen \
    | awk '/Apple_HFS/ {print $NF}')"
ln -s /Applications "$MOUNT_POINT/Applications" 2>/dev/null || true
hdiutil detach "$MOUNT_POINT"

# Convert to compressed read-only
hdiutil convert "$DMG_TEMP" -format UDZO -o "$FINAL_DMG"
rm -f "$DMG_TEMP"

# ─── Step 10: Notarize + staple the .dmg ─────────────────────────────────────
echo "==> Step 10: Notarizing .dmg"
_notarize "$FINAL_DMG"
echo "==> Step 10b: Stapling .dmg"
xcrun stapler staple "$FINAL_DMG"
spctl --assess --type install -vvv "$FINAL_DMG"

# ─── Step 11: SHA256 checksums ────────────────────────────────────────────────
echo "==> Step 11: Generating SHA256 checksums"
shasum -a 256 "$FINAL_PKG" > "${FINAL_PKG}.sha256"
shasum -a 256 "$FINAL_DMG" > "${FINAL_DMG}.sha256"
cat "${FINAL_PKG}.sha256"
cat "${FINAL_DMG}.sha256"

# ─── Step 12: Copy artifacts to releases/ ────────────────────────────────────
echo "==> Step 12: Copying artifacts to releases/"
mkdir -p "$RELEASES_DIR"
cp "$FINAL_PKG"          "$RELEASES_DIR/"
cp "${FINAL_PKG}.sha256" "$RELEASES_DIR/"
cp "$FINAL_DMG"          "$RELEASES_DIR/"
cp "${FINAL_DMG}.sha256" "$RELEASES_DIR/"

echo ""
echo "==> Done — ready to publish."
echo ""
echo "    Artifacts in releases/:"
echo "      ${VERSIONED_NAME}.pkg"
echo "      ${VERSIONED_NAME}.pkg.sha256"
echo "      ${VERSIONED_NAME}.dmg"
echo "      ${VERSIONED_NAME}.dmg.sha256"
echo ""
echo "    Upload to: https://interlinedlist.com/downloads/apple/"
echo ""
echo "    Then sign the .pkg with Sparkle's sign_update to get"
echo "    the edSignature for appcast.xml — see scripts/README for steps."
