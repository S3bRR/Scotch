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
  MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || true)"
  [[ "$MIN_OS" == "26.0" ]] || { echo "Expected LSMinimumSystemVersion 26.0, got: ${MIN_OS:-missing}"; exit 1; }
fi

# Resource presence checks.
EXPECTED_FILES=(
  "$APP_BUNDLE_PATH/Contents/Resources/Scotch_ScotchRuntime.bundle/libMoltenVK_shim.c"
  "$APP_BUNDLE_PATH/Contents/Resources/Scotch_ScotchRuntime.bundle/libscotch_gpu_spoof.dylib"
)
for file in "${EXPECTED_FILES[@]}"; do
  [[ -e "$file" ]] || { echo "Missing required artifact: $file"; exit 1; }
done

if command -v lipo >/dev/null 2>&1; then
  SHIM_ARCHES="$(lipo -archs "$APP_BUNDLE_PATH/Contents/Resources/Scotch_ScotchRuntime.bundle/libscotch_gpu_spoof.dylib")"
  [[ " $SHIM_ARCHES " == *" x86_64 "* ]] || { echo "GPU spoof shim missing x86_64 architecture: $SHIM_ARCHES"; exit 1; }
fi

if command -v codesign >/dev/null 2>&1; then
  while IFS= read -r -d '' bundled_file; do
    if file -b "$bundled_file" | grep -q "Mach-O"; then
      codesign --verify --strict --verbose=2 "$bundled_file" >/dev/null
    fi
  done < <(find "$APP_BUNDLE_PATH" -type f -print0)
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH" >/dev/null
fi

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
