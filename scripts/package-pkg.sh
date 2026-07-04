#!/usr/bin/env bash
# package-pkg.sh
# Wraps the notarized .app in a flat .pkg installer for distribution.
#
# The .pkg is signed with a "Developer ID Installer" certificate
# (separate from the "Developer ID Application" cert used for the .app).
# Both are issued from your Apple Developer account.
#
# Prerequisites:
#   • Developer ID Installer certificate in Keychain
#   • pkgbuild + productbuild (bundled with Xcode command-line tools)
#
# Usage:
#   ./scripts/package-pkg.sh [version]
#
# Example:
#   ./scripts/package-pkg.sh 1.0.0
#
# Outputs:
#   build/Release/InterlinedList-1.0.0.pkg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/Release"
APP_PATH="$BUILD_DIR/InterlinedList.app"

VERSION="${1:-0.1.0}"
PKG_NAME="InterlinedList-$VERSION.pkg"
COMPONENT_PKG="$BUILD_DIR/InterlinedList-component.pkg"
FINAL_PKG="$BUILD_DIR/$PKG_NAME"

# The install location for the .app inside the package.
INSTALL_LOCATION="/Applications"

# Your Developer ID Installer certificate identity (as shown in Keychain).
# Run: security find-identity -v -p basic | grep "Developer ID Installer"
INSTALLER_IDENTITY="Developer ID Installer"

# ─── Check inputs ─────────────────────────────────────────────────────────────
if [[ ! -d "$APP_PATH" ]]; then
    echo "✘ $APP_PATH not found. Run build-release.sh and notarize.sh first."
    exit 1
fi

echo "==> Building component package for InterlinedList.app…"
pkgbuild \
    --component "$APP_PATH" \
    --install-location "$INSTALL_LOCATION" \
    --version "$VERSION" \
    --identifier "com.interlinedlist.macos.pkg" \
    "$COMPONENT_PKG"

echo "==> Building signed product package…"
productbuild \
    --package "$COMPONENT_PKG" \
    --sign "$INSTALLER_IDENTITY" \
    --version "$VERSION" \
    "$FINAL_PKG"

rm -f "$COMPONENT_PKG"

echo "==> Verifying package signature…"
pkgutil --check-signature "$FINAL_PKG"

echo ""
echo "✓ $FINAL_PKG is ready for distribution."
echo ""
echo "Distribution checklist:"
echo "  1. Upload $PKG_NAME to your release server / CDN"
echo "  2. Update the Sparkle appcast at your SUFeedURL"
echo "  3. Sign the .pkg delta with ./scripts/sparkle-sign.sh (once Sparkle is integrated)"
