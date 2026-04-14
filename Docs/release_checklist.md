# Scotch Release Checklist

## Packaging
- [ ] Build `ScotchApp`, `ScotchCmd`, and `ScotchThumbnail` in release configuration.
- [ ] Run `scripts/package_release.sh` to stage the `.app` bundle and build the DMG.
- [ ] Confirm runtime-support resources are present in the bundle:
  - `VulkanSpoof/libMoltenVK_shim.c` (compiled at runtime on first setup)
  - `cabextract` (required by Winetricks)

## Entitlements and Permissions
- [ ] `NSAppleEventsUsageDescription` is present in `Info.plist` (Terminal integration).
- [ ] App entitlements match the shipping profile (`Scotch.entitlements`).
- [ ] Validate launch on a clean Apple Silicon machine running macOS 26.

## Signing and Notarization
- [ ] Codesign app bundle (ad-hoc `-` is the default; Developer ID if available).
- [ ] Notarize via `xcrun notarytool` (requires Developer ID).
- [ ] Staple the notarization ticket.
- [ ] Verify the notarization state on a clean machine.

## Final gate
- [ ] Run `scripts/verify_release_bundle.sh <path-to-Scotch.app>`.
- [ ] Walk through `Docs/manual_qa_matrix.md`.
- [ ] Tag the release and upload the DMG.
