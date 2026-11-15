#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${SCOTCH_RELEASE_DIR:-$ROOT_DIR/.release}"
OUT_DIR="$(python3 - "$ROOT_DIR" "$OUT_DIR" <<'PYOUT'
from pathlib import Path
import sys
root = (Path(sys.argv[1]) / '.release').resolve()
output = Path(sys.argv[2]).resolve()
if output != root and root not in output.parents:
    raise SystemExit('Release output must be inside the repository .release directory')
print(output)
PYOUT
)"
APP_NAME="Scotch"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
MOUNT_DIR=""
cleanup_mount() {
  if [[ -n "$MOUNT_DIR" ]]; then hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true; fi
}
trap cleanup_mount EXIT

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"

# Keep the resource layout used and validated by the 1.2.x releases.
# Swift's Xcode build backend nests these resources differently.
read -r -a EXTRA_BUILD_FLAGS <<< "${SWIFT_BUILD_FLAGS:---build-system native}"
swift build -c release ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"} --product ScotchApp
swift build -c release ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"} --product ScotchCmd
swift build -c release ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"} --product ScotchThumbnail
APP_BIN="$ROOT_DIR/.build/release/ScotchApp"
CMD_BIN="$ROOT_DIR/.build/release/ScotchCmd"
THUMBNAIL_BIN="$ROOT_DIR/.build/release/ScotchThumbnail"

# Runtime/package parity checks for required artifacts.
REQUIRED_PATHS=(
  "$ROOT_DIR/Sources/ScotchRuntime/Resources/VulkanSpoof/libMoltenVK_shim.c"
  "$ROOT_DIR/Sources/ScotchRuntime/Resources/VulkanSpoof/libscotch_gpu_spoof.dylib"
  "$ROOT_DIR/Sources/ScotchRuntime/Resources/GraphicsSupport.tar.xz"
  "$ROOT_DIR/Sources/ScotchApp/Info.plist"
  "$ROOT_DIR/Sources/ScotchApp/Scotch.entitlements"
  "$ROOT_DIR/Sources/ScotchThumbnail/Info.plist"
  "$ROOT_DIR/Sources/ScotchThumbnail/ScotchThumbnail.entitlements"
)
for path in "${REQUIRED_PATHS[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required release artifact source: $path"
    exit 1
  fi
done

if command -v lipo >/dev/null 2>&1; then
  SHIM_ARCHES="$(lipo -archs "$ROOT_DIR/Sources/ScotchRuntime/Resources/VulkanSpoof/libscotch_gpu_spoof.dylib")"
  if [[ " $SHIM_ARCHES " != *" x86_64 "* ]]; then
    echo "GPU spoof shim must include x86_64, got: $SHIM_ARCHES"
    exit 1
  fi
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/PlugIns"
cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/ScotchApp"
cp "$CMD_BIN" "$APP_BUNDLE/Contents/MacOS/ScotchCmd"
cp "$ROOT_DIR/Sources/ScotchApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

THUMBNAIL_APPEX="$APP_BUNDLE/Contents/PlugIns/ScotchThumbnail.appex"
mkdir -p "$THUMBNAIL_APPEX/Contents/MacOS"
cp "$THUMBNAIL_BIN" "$THUMBNAIL_APPEX/Contents/MacOS/ScotchThumbnail"
cp "$ROOT_DIR/Sources/ScotchThumbnail/Info.plist" "$THUMBNAIL_APPEX/Contents/Info.plist"

for bundle in "$ROOT_DIR"/.build/release/*.bundle; do
  if [[ -e "$bundle" ]]; then
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
  fi
done

find "$APP_BUNDLE/Contents/Resources" -name cabextract -exec chmod +x {} \;

ICON_SRC="$ROOT_DIR/Sources/ScotchApp/Assets.xcassets/AppIcon.appiconset"
if [[ -d "$ICON_SRC" ]] && command -v iconutil >/dev/null 2>&1; then
  ICONSET_TMP="$OUT_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_TMP"
  mkdir -p "$ICONSET_TMP"
  cp "$ICON_SRC/16.png"   "$ICONSET_TMP/icon_16x16.png"   2>/dev/null || true
  cp "$ICON_SRC/32.png"   "$ICONSET_TMP/icon_16x16@2x.png" 2>/dev/null || true
  cp "$ICON_SRC/32.png"   "$ICONSET_TMP/icon_32x32.png"   2>/dev/null || true
  cp "$ICON_SRC/64.png"   "$ICONSET_TMP/icon_32x32@2x.png" 2>/dev/null || true
  cp "$ICON_SRC/128.png"  "$ICONSET_TMP/icon_128x128.png" 2>/dev/null || true
  cp "$ICON_SRC/256.png"  "$ICONSET_TMP/icon_128x128@2x.png" 2>/dev/null || true
  cp "$ICON_SRC/256.png"  "$ICONSET_TMP/icon_256x256.png" 2>/dev/null || true
  cp "$ICON_SRC/512.png"  "$ICONSET_TMP/icon_256x256@2x.png" 2>/dev/null || true
  cp "$ICON_SRC/512.png"  "$ICONSET_TMP/icon_512x512.png" 2>/dev/null || true
  cp "$ICON_SRC/1024.png" "$ICONSET_TMP/icon_512x512@2x.png" 2>/dev/null || true
  iconutil -c icns -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$ICONSET_TMP"
  rm -rf "$ICONSET_TMP"
fi

# Sparkle is an app-only dependency. Preserve its framework symlinks and
# nested updater services when assembling our custom SwiftPM app bundle.
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/release/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Missing Sparkle framework"; exit 1; }
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

if command -v codesign >/dev/null 2>&1; then
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
  while IFS= read -r -d '' framework_file; do
    if file -b "$framework_file" | grep -q "Mach-O"; then
      codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --preserve-metadata=identifier,entitlements "$framework_file"
    fi
  done < <(find "$APP_BUNDLE/Contents/Frameworks" -type f -print0)
  while IFS= read -r -d '' helper; do
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --preserve-metadata=identifier,entitlements "$helper"
  done < <(find "$APP_BUNDLE/Contents/Frameworks" -depth -type d \( -name '*.xpc' -o -name '*.app' \) -print0)
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  while IFS= read -r -d '' resource_file; do
    if file -b "$resource_file" | grep -q "Mach-O"; then
      codesign --force --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        "$resource_file"
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources" -type f -print0)

  codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Sources/ScotchApp/Scotch.entitlements" \
    --options runtime \
    "$APP_BUNDLE/Contents/MacOS/ScotchCmd"
  codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Sources/ScotchThumbnail/ScotchThumbnail.entitlements" \
    --options runtime \
    "$THUMBNAIL_APPEX/Contents/MacOS/ScotchThumbnail"
  codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Sources/ScotchThumbnail/ScotchThumbnail.entitlements" \
    --options runtime \
    "$THUMBNAIL_APPEX"
  codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ROOT_DIR/Sources/ScotchApp/Scotch.entitlements" \
    --options runtime \
    "$APP_BUNDLE"
fi

bash "$ROOT_DIR/scripts/verify_release_bundle.sh" "$APP_BUNDLE"

# Prepare complete corresponding source as a separate release asset. Keep the
# mounted installer focused on Scotch.app and the Applications shortcut.
python3 "$ROOT_DIR/scripts/graphics/package_sources.py"
cp "$ROOT_DIR/.build/graphics-support/ScotchGraphicsSources.tar.xz" "$OUT_DIR/"
(cd "$OUT_DIR" && shasum -a 256 ScotchGraphicsSources.tar.xz > ScotchGraphicsSources.tar.xz.sha256)

if command -v hdiutil >/dev/null 2>&1; then
  DMG_PATH="$OUT_DIR/Scotch.dmg"
  STAGING="$OUT_DIR/dmg-staging"
  RW_DMG="$OUT_DIR/Scotch.rw.dmg"
  VOLUME_NAME="Scotch"

  rm -rf "$STAGING" "$DMG_PATH" "$RW_DMG"
  mkdir -p "$STAGING"
  cp -R "$APP_BUNDLE" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

  hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -plist > "$OUT_DIR/mount.plist"
  MOUNT_DIR="$(python3 - "$OUT_DIR/mount.plist" <<'PYMOUNT'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    image = plistlib.load(source)
print(next(entity['mount-point'] for entity in image['system-entities'] if 'mount-point' in entity))
PYMOUNT
)"

  # Give Finder a moment to index the mounted volume before scripting it.
  sleep 2

  osascript <<OSA
tell application "Finder"
  set targetDisk to disk of (POSIX file "$MOUNT_DIR" as alias)
  tell targetDisk
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 120, 1100, 700}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 144
    set text size of theViewOptions to 14
    delay 1
    set position of item "Scotch.app" of container window to {180, 220}
    set position of item "Applications" of container window to {520, 220}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

  sync
  hdiutil detach "$MOUNT_DIR" >/dev/null
  rmdir "$MOUNT_DIR" 2>/dev/null || true
  MOUNT_DIR=""

  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
  rm -f "$RW_DMG"
  rm -rf "$STAGING"
  (cd "$OUT_DIR" && shasum -a 256 Scotch.dmg > Scotch.dmg.sha256)

  echo "Created $DMG_PATH"
else
  echo "hdiutil unavailable; skipped DMG generation"
fi

echo "Release package staging complete at $APP_BUNDLE"
echo "Corresponding source release assets: $OUT_DIR/ScotchGraphicsSources.tar.xz and .sha256"
