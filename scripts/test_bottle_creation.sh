#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --product ScotchCmd
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
PROOF_DIR="$PWD/.build/bottle-creation-proof"
mkdir -p "$PROOF_DIR"
swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" scripts/BottleCreationProbe.swift \
  "$BUILD_DIR"/ScotchDomain.build/*.o "$BUILD_DIR"/ScotchInfrastructure.build/*.o \
  "$BUILD_DIR"/ScotchRuntime.build/*.o -o "$PROOF_DIR/BottleCreationProbe"

# Match the installed app layout, including spaces and Finder's minimal PATH.
APP="$PROOF_DIR/Relocated Scotch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROOF_DIR/BottleCreationProbe" "$APP/Contents/MacOS/"
rm -rf "$APP/Contents/Resources/Scotch_ScotchRuntime.bundle"
cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" "$APP/Contents/Resources/"
PATH=/usr/bin:/bin:/usr/sbin:/sbin "$APP/Contents/MacOS/BottleCreationProbe" "$@"
