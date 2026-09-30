#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCE_BUNDLE="${1:-$ROOT_DIR/.build/release/Scotch_ScotchRuntime.bundle}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
APP_BUNDLE="$TEST_DIR/Relocated Scotch.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

# Compile the actual resolver into a standalone probe. It has no build-path
# fallback, so this checks real Bundle.main behavior after moving into an app.
swiftc -parse-as-library \
  "$ROOT_DIR/Sources/ScotchRuntime/Runtime/RuntimeResources.swift" \
  "$ROOT_DIR/scripts/RuntimeResourceProbe.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/ResourceProbe"
"$APP_BUNDLE/Contents/MacOS/ResourceProbe"

# A missing resource must fail normally instead of terminating with SIGTRAP.
rm "$APP_BUNDLE/Contents/Resources/Scotch_ScotchRuntime.bundle/cabextract"
set +e
"$APP_BUNDLE/Contents/MacOS/ResourceProbe" >"$TEST_DIR/missing-resource.log" 2>&1
PROBE_STATUS=$?
set -e
if [[ "$PROBE_STATUS" != 1 ]]; then
  echo "Expected a normal missing-resource error (exit 1), got exit $PROBE_STATUS"
  cat "$TEST_DIR/missing-resource.log"
  exit 1
fi
echo "Relocated resource lookup passed."
