#!/usr/bin/env bash
# Build and launch the app from the terminal (like hitting Run in Xcode).
#
#   scripts/run.sh            # build + launch the InterlinedList app (default)
#   scripts/run.sh agent      # build + launch the document-sync menu-bar agent
#   scripts/run.sh --release  # build the app in Release instead of Debug
#
# Optional env:
#   CONFIGURATION=Debug|Release   (default Debug for the app)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

TARGET="app"
CONFIGURATION="${CONFIGURATION:-Debug}"
for arg in "$@"; do
    case "$arg" in
        agent|--agent) TARGET="agent" ;;
        --release)     CONFIGURATION="Release" ;;
        --debug)       CONFIGURATION="Debug" ;;
        -h|--help)
            sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $arg (try --help)"; exit 2 ;;
    esac
done

if [[ "$TARGET" == "agent" ]]; then
    # The sync agent is a SwiftPM menu-bar app assembled into an .app bundle.
    echo "==> Building document-sync agent"
    CONFIG=release bash "$SCRIPT_DIR/../SyncAgent/scripts/build-app.sh"
    AGENT_APP="$ROOT_DIR/SyncAgent/build/InterlinedListSync.app"
    [[ -d "$AGENT_APP" ]] || { echo "!! Agent build did not produce $AGENT_APP"; exit 1; }
    echo "==> Launching $AGENT_APP (look for the icon in the menu bar)"
    open "$AGENT_APP"
    exit 0
fi

# ─── Main InterlinedList app ─────────────────────────────────────────────────
PROJECT="$ROOT_DIR/InterlinedList.xcodeproj"
SCHEME="InterlinedList"
DERIVED_DIR="$ROOT_DIR/build/run"
APP_PATH="$DERIVED_DIR/Build/Products/$CONFIGURATION/InterlinedList.app"
RUN_ENTITLEMENTS="$ROOT_DIR/scripts/run.entitlements"

# Local run uses ad-hoc signing ("-") so it needs no Apple Developer
# provisioning profile. The production `keychain-access-groups` entitlement is
# App-ID-bound and *requires* a profile, so for local runs we sign against a
# reduced entitlements file (scripts/run.entitlements) that drops the shared
# Keychain group. The app still runs — it just stores its token in the
# non-shared Keychain item (KeychainTokenStore degrades gracefully), so
# cross-process token sharing with the sync agent is unavailable locally.
echo "==> Building $SCHEME ($CONFIGURATION, ad-hoc signed)"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_ENTITLEMENTS="$RUN_ENTITLEMENTS" \
    | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

[[ -d "$APP_PATH" ]] || { echo "!! Build did not produce $APP_PATH"; exit 1; }

echo "==> Launching $APP_PATH"
open "$APP_PATH"
