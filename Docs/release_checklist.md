# Scotch Release Checklist

## Packaging
- [ ] Build `ScotchApp`, `ScotchCmd`, and `ScotchThumbnail` in release configuration.
- [ ] Run `scripts/package_release.sh` to stage the `.app` bundle and build the DMG.
- [ ] Confirm runtime-support resources are present in the bundle:
  - `VulkanSpoof/libMoltenVK_shim.c` (compiled at runtime on first setup)
  - `cabextract` (required by Winetricks)
  - `GraphicsSupport.tar.xz` and its generated verification hashes
- [ ] Keep only Scotch.app and Applications in the mounted DMG.
- [ ] Upload ScotchGraphicsSources.tar.xz and its checksum beside the DMG.
- [ ] Run `python3 scripts/verify_release_artifacts.py .release/build16`.
- [ ] Confirm native modules have no local build/Homebrew dependencies and target macOS 26.

## Entitlements and Permissions
- [ ] `NSAppleEventsUsageDescription` is present in `Info.plist` (Terminal integration).
- [ ] App entitlements match the shipping profile (`Scotch.entitlements`).
- [ ] Validate launch on a clean Apple Silicon machine running macOS 26.

## Signing and Notarization
- [ ] Codesign app bundle (ad-hoc `-` is the default; Developer ID if available).
- [ ] Notarize via `xcrun notarytool` (requires Developer ID).
- [ ] Staple the notarization ticket.
- [ ] Verify the notarization state on a clean machine.

## Update publication
- [ ] Run `bash scripts/test_updates.sh` and `python3 scripts/test_app_updater.py` after packaging.
- [ ] Prepare the signed appcast with `scripts/updates/prepare_appcast.py`.
- [ ] Keep the app/runtime signing keys securely backed up outside the repository.
- [ ] Upload approved release assets before advertising them in a signed feed.
- [ ] Run `scripts/updates/verify_public_assets.py` before feed publication.
- [ ] Follow `Docs/updates.md`; public deployment requires release approval.

## Final gate
- [ ] Run `bash scripts/test_live_runtime.sh` on idle hardware: all backends, bitness, combined Zink, GUI launch, repair and prefix recovery.
- [ ] Run `bash scripts/test_runtime_installation.sh` (uses the pinned upstream Mesa archive; an existing archive can be passed as the first argument).
- [ ] Run `scripts/verify_release_bundle.sh <path-to-Scotch.app>`.
- [ ] Walk through `Docs/manual_qa_matrix.md`.
- [ ] Test the reported game and other supported GPU/macOS combinations.
- [ ] For new native profiles, retain support for existing pinned runtime sets, use new immutable IDs, and raise minimumAppBuild.
- [ ] Obtain explicit release approval before pushing, tagging or uploading the DMG.
