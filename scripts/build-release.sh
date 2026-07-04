#!/usr/bin/env bash
# build-release.sh
# Builds a signed, notarization-ready release of InterlinedList.
#
# Prerequisites:
#   • Xcode command-line tools: xcode-select --install
#   • Developer ID Application certificate in Keychain
#   • Matching provisioning profile (or Automatic signing)
#
# Usage:
#   ./scripts/build-release.sh [--arch arm64|x86_64|universal]
#
# Outputs:
#   build/Release/InterlinedList.app   — signed .app bundle
#
# After this script: run ./scripts/notarize.sh to submit to Apple and
# staple the ticket, then ./scripts/package-pkg.sh to wrap in a .pkg.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/Release"
SCHEME="InterlinedList"
PROJECT="$ROOT_DIR/InterlinedList.xcodeproj"
BUNDLE_ID="com.interlinedlist.macos"

# ─── Optional arch flag ───────────────────────────────────────────────────────
ARCH_FLAG=""
ARCH="${1:-}"
case "$ARCH" in
  --arch=arm64)    ARCH_FLAG="ARCHS=arm64" ;;
  --arch=x86_64)   ARCH_FLAG="ARCHS=x86_64" ;;
  --arch=universal | "") : ;;  # default: build for active arch (Xcode chooses)
  *) echo "Unknown arch: $ARCH"; exit 1 ;;
esac

echo "==> Building $SCHEME (Release)…"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  archive \
  $ARCH_FLAG \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  CODE_SIGN_STYLE=Manual \
  PROVISIONING_PROFILE_SPECIFIER="" \
  | xcpretty --color || true

echo "==> Exporting .app from archive…"
xcodebuild \
  -exportArchive \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist "$SCRIPT_DIR/export-options.plist" \
  | xcpretty --color || true

echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR/$SCHEME.app"
spctl --assess --type exec --verbose "$BUILD_DIR/$SCHEME.app"

echo ""
echo "✓ $BUILD_DIR/$SCHEME.app is built and signed."
echo "  Next: ./scripts/notarize.sh"
