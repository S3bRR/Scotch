#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE_PATH="${1:-}"

if [[ -z "$APP_BUNDLE_PATH" ]]; then
  echo "Usage: scripts/verify_release_bundle.sh /path/to/Scotch.app"
  exit 2
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle not found: $APP_BUNDLE_PATH"
  exit 1
fi

# Entitlement check (best-effort).
if command -v codesign >/dev/null 2>&1; then
  echo "Entitlements:"
  codesign -d --entitlements :- "$APP_BUNDLE_PATH" 2>/dev/null || echo "Unable to read entitlements"
fi

# Apple Events usage string check.
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "$INFO_PLIST" >/dev/null 2>&1 \
    && echo "NSAppleEventsUsageDescription: present" \
    || echo "NSAppleEventsUsageDescription: missing"
fi

# Resource presence checks.
EXPECTED_FILES=(
  "$ROOT_DIR/Sources/ScotchRuntime/Resources/VulkanSpoof/libMoltenVK_shim.c"
)
for file in "${EXPECTED_FILES[@]}"; do
  [[ -e "$file" ]] || { echo "Missing source artifact: $file"; exit 1; }
done

# QuickLook extension checks.
THUMBNAIL_APPEX="$APP_BUNDLE_PATH/Contents/PlugIns/ScotchThumbnail.appex"
if [[ -d "$THUMBNAIL_APPEX" ]]; then
  [[ -f "$THUMBNAIL_APPEX/Contents/Info.plist" ]] || { echo "Missing thumbnail extension Info.plist"; exit 1; }
  [[ -x "$THUMBNAIL_APPEX/Contents/MacOS/ScotchThumbnail" ]] || { echo "Missing thumbnail extension executable"; exit 1; }
  echo "QuickLook extension: present"
else
  echo "QuickLook extension: missing"
  exit 1
fi

# Architecture info.
if [[ -x "$APP_BUNDLE_PATH/Contents/MacOS/ScotchApp" ]] && command -v lipo >/dev/null 2>&1; then
  lipo -info "$APP_BUNDLE_PATH/Contents/MacOS/ScotchApp"
fi

echo "Release bundle verification completed."
