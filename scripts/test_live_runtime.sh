#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native -c release --product ScotchCmd
BUILD_DIR="$(swift build --build-system native -c release --show-bin-path)"
PROOF_DIR="$PWD/.build/live-runtime-proof"
mkdir -p "$PROOF_DIR"
x86_64-w64-mingw32-gcc scripts/D3DMetalSmoke.c -o "$PROOF_DIR/D3DMetalSmoke.exe" -static -ldxguid -lole32
x86_64-w64-mingw32-gcc scripts/D3D12AutoSmoke.c -o "$PROOF_DIR/D3D12AutoSmoke.exe" -static -ld3d12 -ldxguid -lole32
i686-w64-mingw32-gcc scripts/D3DMetalSmoke.c -o "$PROOF_DIR/D3DMetalSmoke32.exe" -static -ldxguid -lole32
x86_64-w64-mingw32-gcc scripts/ZinkSmoke.c -o "$PROOF_DIR/ZinkSmoke.exe" -static -lopengl32 -lgdi32
i686-w64-mingw32-gcc scripts/ZinkSmoke.c -o "$PROOF_DIR/ZinkSmoke32.exe" -static -lopengl32 -lgdi32
x86_64-w64-mingw32-gcc scripts/CombinedGraphicsSmoke.c -o "$PROOF_DIR/CombinedSmoke.exe" -static -ldxguid -lole32 -lopengl32 -lgdi32
i686-w64-mingw32-gcc scripts/CombinedGraphicsSmoke.c -o "$PROOF_DIR/CombinedSmoke32.exe" -static -ldxguid -lole32 -lopengl32 -lgdi32
swiftc -swift-version 6 -parse-as-library -I "$BUILD_DIR/Modules" scripts/LiveRuntimeProbe.swift \
  "$BUILD_DIR"/ScotchDomain.build/*.o "$BUILD_DIR"/ScotchInfrastructure.build/*.o "$BUILD_DIR"/ScotchRuntime.build/*.o \
  -o "$PROOF_DIR/LiveRuntimeProbe"
cp -R "$BUILD_DIR/Scotch_ScotchRuntime.bundle" "$PROOF_DIR/"
"$PROOF_DIR/LiveRuntimeProbe" "$PROOF_DIR/D3DMetalSmoke.exe" "$PROOF_DIR" "$@"
