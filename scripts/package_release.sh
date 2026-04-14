#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.release"
APP_NAME="Scotch"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$ROOT_DIR"

swift build -c release --product ScotchApp
swift build -c release --product ScotchCmd
swift build -c release --product ScotchThumbnail
APP_BIN="$ROOT_DIR/.build/release/ScotchApp"
CMD_BIN="$ROOT_DIR/.build/release/ScotchCmd"
THUMBNAIL_BIN="$ROOT_DIR/.build/release/ScotchThumbnail"

# Runtime/package parity checks for required artifacts.
REQUIRED_PATHS=(
  "$ROOT_DIR/Sources/ScotchRuntime/Resources/VulkanSpoof/libMoltenVK_shim.c"
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

if command -v codesign >/dev/null 2>&1; then
  CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
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

if command -v hdiutil >/dev/null 2>&1; then
  DMG_PATH="$OUT_DIR/Scotch.dmg"
  STAGING="$OUT_DIR/dmg-staging"
  RW_DMG="$OUT_DIR/Scotch.rw.dmg"
  VOLUME_NAME="Scotch"

  # Detach any volume named "Scotch" (or collision-suffixed variants) so the
  # AppleScript window-layout pass unambiguously targets our new image.
  for vol in /Volumes/Scotch /Volumes/Scotch\ 1 /Volumes/Scotch\ 2 /Volumes/Scotch\ 3; do
    if [[ -d "$vol" ]]; then
      echo "Detaching existing mount: $vol"
      hdiutil detach "$vol" -force >/dev/null 2>&1 || true
    fi
  done

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

  # Let macOS auto-mount at /Volumes/<VOLUME_NAME> so Finder's `tell disk "Scotch"`
  # resolves unambiguously. Passing -mountpoint forces the basename of the mount
  # path as the Finder-visible name, which breaks the AppleScript lookup.
  hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null
  MOUNT_DIR="/Volumes/$VOLUME_NAME"

  # Give Finder a moment to index the mounted volume before scripting it.
  sleep 2

  osascript <<OSA
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 120, 1100, 560}
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

  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
  rm -f "$RW_DMG"
  rm -rf "$STAGING"

  echo "Created $DMG_PATH"
else
  echo "hdiutil unavailable; skipped DMG generation"
fi

echo "Release package staging complete at $APP_BUNDLE"
