#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swift build --build-system native -c release --product ScotchCmd
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" \
  "$ROOT_DIR/scripts/UpdateProbe.swift" \
  "$BUILD_DIR"/ScotchDomain.build/*.o "$BUILD_DIR"/ScotchInfrastructure.build/*.o "$BUILD_DIR"/ScotchRuntime.build/*.o \
  -o "$TEST_DIR/UpdateProbe"
cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" "$TEST_DIR/"
if [[ " $* " != *" --feed-only "* ]]; then
  ENGINE_IMAGE="${SCOTCH_TEST_ENGINE_IMAGE:-$ROOT_DIR/.build/runtime-fixtures/WineForge-0.6.0.3.dmg}"
  if [[ ! -f "$ENGINE_IMAGE" ]]; then
    mkdir -p "$(dirname "$ENGINE_IMAGE")"
    curl --fail --location --retry 2 --output "$ENGINE_IMAGE" https://github.com/Alien4042x/WineForge/releases/download/0.6.0.3/WineForge.dmg
  fi
  export SCOTCH_TEST_ENGINE_IMAGE="$ENGINE_IMAGE"
fi
"$TEST_DIR/UpdateProbe" "$ROOT_DIR" "$@"
