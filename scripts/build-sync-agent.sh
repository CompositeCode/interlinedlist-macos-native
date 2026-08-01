#!/usr/bin/env bash
# Builds the InterlinedList document-sync agent into a (optionally signed) .app.
# Thin wrapper over SyncAgent/scripts/build-app.sh that forwards the release
# signing identity. Prints the resulting .app path on the last line.
#
#   CODESIGN_IDENTITY="Developer ID Application: … (BJA9558E4B)" \
#     bash scripts/build-sync-agent.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="$ROOT_DIR/SyncAgent"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    export APPLE_DEVELOPER_ID_APPLICATION="$CODESIGN_IDENTITY"
fi

CONFIG=release bash "$AGENT_DIR/scripts/build-app.sh"

echo "$AGENT_DIR/build/InterlinedListSync.app"
