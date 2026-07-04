#!/usr/bin/env bash
# store-notarization-profile.sh
#
# One-time helper: stores Apple ID + app-specific password into the login
# keychain under the profile name `NotarizationProfile`, so subsequent runs
# of `scripts/notarize-and-package.sh` can pass
# `--keychain-profile NotarizationProfile` without exposing credentials on
# the command line or in shell history.
#
# Run this ONCE per machine before the first notarization. Rerun only if
# credentials rotate.
#
# Required env vars:
#   APPLE_ID              — Apple ID email (e.g. dev@example.com)
#   APPLE_TEAM_ID         — 10-char Team ID (e.g. ABCDE12345)
#   NOTARIZATION_PASSWORD — app-specific password created at
#                           https://appleid.apple.com  (NOT your Apple ID
#                           password). Format: xxxx-xxxx-xxxx-xxxx.
#
# Example:
#   APPLE_ID=you@example.com \
#   APPLE_TEAM_ID=ABCDE12345 \
#   NOTARIZATION_PASSWORD=xxxx-xxxx-xxxx-xxxx \
#       ./scripts/store-notarization-profile.sh

set -euo pipefail

PROFILE_NAME="NotarizationProfile"

usage() {
    cat <<EOF
Usage: APPLE_ID=<email> APPLE_TEAM_ID=<team> NOTARIZATION_PASSWORD=<pw> \\
           $(basename "$0")

Stores notarization credentials in the login keychain under the profile
name '${PROFILE_NAME}'. Run once per machine.
EOF
}

: "${APPLE_ID:?APPLE_ID is required. $(usage)}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required. $(usage)}"
: "${NOTARIZATION_PASSWORD:?NOTARIZATION_PASSWORD is required (app-specific password). $(usage)}"

echo "==> Storing notarization credentials as keychain profile '${PROFILE_NAME}'…"
xcrun notarytool store-credentials "${PROFILE_NAME}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${NOTARIZATION_PASSWORD}"

echo ""
echo "Done. You can now run scripts/notarize-and-package.sh without"
echo "passing credentials — it will read them from keychain profile"
echo "'${PROFILE_NAME}' via 'xcrun notarytool submit --keychain-profile'."
