#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --product ScotchCmd
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
mkdir -p .build/program-graphics-tests
printf '#include <unistd.h>\nint main(void) { for (;;) pause(); }\n' > .build/program-graphics-tests/owned-process.c
clang .build/program-graphics-tests/owned-process.c -o .build/program-graphics-tests/wine64-prefix-probe
swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" scripts/ProgramGraphicsProbe.swift \
  "$BUILD_DIR"/ScotchDomain.build/*.o "$BUILD_DIR"/ScotchInfrastructure.build/*.o \
  "$BUILD_DIR"/ScotchRuntime.build/*.o -o .build/program-graphics-tests/ProgramGraphicsProbe
cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" .build/program-graphics-tests/
.build/program-graphics-tests/ProgramGraphicsProbe
