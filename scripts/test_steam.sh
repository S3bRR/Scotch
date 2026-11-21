#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/steam-tests
swiftc -swift-version 6 -parse-as-library scripts/SteamCompatibilityProbe.swift \
  Sources/ScotchRuntime/Tools/SteamLaunchPolicy.swift \
  Sources/ScotchRuntime/Tools/SteamWebHelperLauncher.swift \
  Sources/ScotchRuntime/Runtime/RuntimeResources.swift -o .build/steam-tests/SteamCompatibilityProbe
.build/steam-tests/SteamCompatibilityProbe
if [[ $# -gt 0 ]]; then
  swift build --build-system native -c release --product ScotchApp
  BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
  swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" scripts/SteamInstallProbe.swift \
    "$BUILD_DIR"/ScotchDomain.build/*.o "$BUILD_DIR"/ScotchInfrastructure.build/*.o \
    "$BUILD_DIR"/ScotchRuntime.build/*.o "$BUILD_DIR"/ScotchPE.build/*.o "$BUILD_DIR"/ScotchFeatures.build/*.o -o .build/steam-tests/SteamInstallProbe
  cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" .build/steam-tests/
  .build/steam-tests/SteamInstallProbe "$@"
fi
