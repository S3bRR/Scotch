#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Use the shipping installer and real archive extraction/signing. The probe
# routes downloads to local fixtures and writes only to uniquely named test roots.
cd "$ROOT_DIR"
swift build --build-system native -c release --product ScotchCmd
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
MESA_ARCHIVE="${1:-$TEST_DIR/mesa3d-26.2.0-release-msvc.7z}"
TOOLKIT_ARCHIVE="${2:-$TEST_DIR/game-porting-toolkit-3.0-3.tar.xz}"
ENGINE_IMAGE="${3:-$TEST_DIR/WineForge.dmg}"
if [[ $# -eq 0 ]]; then
  curl --fail --location --retry 2 --output "$MESA_ARCHIVE" \
    https://github.com/pal1000/mesa-dist-win/releases/download/26.2.0/mesa3d-26.2.0-release-msvc.7z
fi
if [[ $# -lt 2 ]]; then
  curl --fail --location --retry 2 --output "$TOOLKIT_ARCHIVE" \
    https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz
fi
if [[ $# -lt 3 ]]; then
  curl --fail --location --retry 2 --output "$ENGINE_IMAGE" \
    https://github.com/Alien4042x/WineForge/releases/download/0.6.0.3/WineForge.dmg
fi

swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" \
  "$ROOT_DIR/scripts/RuntimeInstallerProbe.swift" \
  "$BUILD_DIR"/ScotchDomain.build/*.o \
  "$BUILD_DIR"/ScotchInfrastructure.build/*.o \
  "$BUILD_DIR"/ScotchRuntime.build/*.o \
  -o "$TEST_DIR/RuntimeInstallerProbe"
cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" "$TEST_DIR/"
"$TEST_DIR/RuntimeInstallerProbe" "$MESA_ARCHIVE" "$TOOLKIT_ARCHIVE" "$ENGINE_IMAGE"
