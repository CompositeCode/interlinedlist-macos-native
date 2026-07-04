#!/usr/bin/env bash
# notarize.sh
# Submits the built .app to Apple's notarization service and staples
# the resulting ticket to the bundle.
#
# Prerequisites:
#   • Apple Developer account with Developer ID Application cert
#   • App-specific password from https://appleid.apple.com (for APPLE_ID)
#   • Or: Keychain credential profile set up with:
#       xcrun notarytool store-credentials "interlinedlist-notarize" \
#         --apple-id "you@example.com" --team-id "ABCDE12345" \
#         --password "@keychain:AC_PASSWORD"
#     Then set NOTARYTOOL_KEYCHAIN_PROFILE below.
#
# Usage:
#   ./scripts/notarize.sh
#
# The script waits for the notarization to complete (typically 1–5 min)
# and then staples the ticket to the .app so it can be validated offline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/Release"
APP_PATH="$BUILD_DIR/InterlinedList.app"
ZIP_PATH="$BUILD_DIR/InterlinedList-notarize.zip"

# ─── Credentials ─────────────────────────────────────────────────────────────
# Option A: environment variables (suitable for CI)
#   APPLE_ID        your@developer.email
#   APPLE_TEAM_ID   your 10-char Team ID
#   APPLE_APP_PASS  app-specific password (or "@keychain:AC_PASSWORD")
#
# Option B: pre-stored Keychain profile (recommended for local dev)
#   Run once:
#     xcrun notarytool store-credentials "interlinedlist-notarize" \
#       --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
#       --password "$APPLE_APP_PASS"
NOTARYTOOL_KEYCHAIN_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-interlinedlist-notarize}"

# ─── Check inputs ─────────────────────────────────────────────────────────────
if [[ ! -d "$APP_PATH" ]]; then
    echo "✘ $APP_PATH not found. Run ./scripts/build-release.sh first."
    exit 1
fi

# ─── Package as zip for submission ────────────────────────────────────────────
echo "==> Creating zip for notarization submission…"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ─── Submit ───────────────────────────────────────────────────────────────────
echo "==> Submitting to Apple Notarization Service…"
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" \
    --wait

# --wait polls until the submission is accepted or rejected (blocking).
# Remove --wait and use --submission-id + notarytool info in CI to avoid
# long-running jobs.

# ─── Staple ───────────────────────────────────────────────────────────────────
echo "==> Stapling notarization ticket to .app…"
xcrun stapler staple "$APP_PATH"

echo "==> Verifying stapled ticket…"
spctl --assess --type exec --verbose "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -f "$ZIP_PATH"

echo ""
echo "✓ $APP_PATH is notarized and stapled."
echo "  Next: ./scripts/package-pkg.sh"
