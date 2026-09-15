#!/bin/bash
#
# gate.sh — the E2E gate from .claude/skills/swift-engineer/assets/e2e-gate-checklist.md,
# run in one command, with the App-target result bundle captured.
#
# The capture is the point (GitHub #82). Two App-target runs have reported
# "Executed N tests, with 1 failure" without naming the test, and neither
# reproduced — so each sighting cost a full investigation and produced nothing.
# `-resultBundlePath` plus `xcrun xcresulttool` turns the next occurrence into a
# test name, which is the difference between a bug report and a rumour.
#
# Usage:
#   scripts/gate.sh              # full gate
#   scripts/gate.sh app          # App target only
#   scripts/gate.sh app 20       # App target, 20 consecutive runs (flake hunt)
#
# Every run's bundle lands in build/test-results/ and is summarised on failure.

set -uo pipefail
cd "$(dirname "$0")/.."

SCHEME=InterlinedList
PROJECT=InterlinedList.xcodeproj
DEST='platform=macOS'
RESULTS_DIR=build/test-results
mkdir -p "$RESULTS_DIR"

MODE="${1:-all}"
ITERATIONS="${2:-1}"
FAILED=0

# Signing is unavailable on CI runners and, per the project's reference note,
# on this machine's App test target — so the gate always disables it rather than
# making each caller remember the override.
NOSIGN=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")

# Prints the failing test identifiers out of a result bundle. Without this the
# only artefact of a failure is a count.
name_failures() {
  local bundle="$1"
  echo "--- failing tests in $bundle"
  if ! xcrun xcresulttool get test-results tests --path "$bundle" --format json 2>/dev/null \
      | python3 -c '
import json, sys
def walk(node):
    for child in node.get("children", []) or []:
        yield from walk(child)
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        yield node.get("nodeIdentifier") or node.get("name")
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(1)
names = [n for root in doc.get("testNodes", []) for n in walk(root)]
if names:
    for n in names:
        print("  FAILED:", n)
else:
    print("  (result bundle parsed, but no failed test cases were listed)")
'; then
    echo "  (could not parse the result bundle; open it with: xed $bundle)"
  fi
}

run_app_tests() {
  local i="$1"
  local bundle="$RESULTS_DIR/app-$(printf '%03d' "$i").xcresult"
  rm -rf "$bundle"
  echo "=== App target tests (run $i/$ITERATIONS)"
  if xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
      -resultBundlePath "$bundle" \
      "${NOSIGN[@]}" 2>&1 | tail -n 40; then
    echo "--- run $i: PASS"
  else
    echo "--- run $i: FAIL"
    name_failures "$bundle"
    FAILED=1
  fi
}

if [ "$MODE" = "all" ]; then
  echo "=== Build"
  xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" "${NOSIGN[@]}" \
    2>&1 | tail -n 5 || FAILED=1

  for pkg in InterlinedKit InterlinedDomain InterlinedPersistence; do
    echo "=== swift test: $pkg"
    swift test --package-path "Packages/$pkg" 2>&1 | tail -n 3 || FAILED=1
  done

  # Anchored at column 0: the unanchored form in the checklist matches the
  # *prose* in file-header comments that say a file does NOT import the kit,
  # which reports a violation on a compliant tree.
  echo "=== Decision 0003: no Kit imports in features"
  if grep -rn "^import InterlinedKit" App/Features App/Navigation App/MenuCommands 2>/dev/null; then
    echo "VIOLATION: Kit imported in a feature layer"
    FAILED=1
  else
    echo "zero hits — OK"
  fi
fi

for ((i = 1; i <= ITERATIONS; i++)); do
  run_app_tests "$i"
done

echo
if [ "$FAILED" -eq 0 ]; then
  echo "GATE: PASS"
else
  echo "GATE: FAIL — see the named tests above; bundles in $RESULTS_DIR"
fi
exit "$FAILED"
