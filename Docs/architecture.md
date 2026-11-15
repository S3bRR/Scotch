# Scotch Architecture

## Layers
- `ScotchApp`: executable entry point and scene bootstrapping.
- `ScotchFeatures`: SwiftUI screens and feature view models.
- `ScotchRuntime`: bottle orchestration, runtime install/update, launch execution, compatibility behavior.
- `ScotchInfrastructure`: filesystem/process/logging/persistence adapters.
- `ScotchDomain`: pure models and use-case protocols.

## Composition
- `ScotchContainer` builds concrete services once and injects protocols into feature view models.
- Runtime services use actors for mutation and process orchestration.
- UI never talks directly to process/file APIs.

## Data layout
All writable state lives under `~/Library/Application Support/com.s3brr.Scotch/`:
- `Libraries/` — Wine, MetalEngine, DXVK, DXMT, D3DMetal, Zink, Graphics, GPU spoof dylib, winetricks
- `Bottles/` — default prefixes
- `Logs/` — launch logs
- `WinetricksCache/` — font/verb downloads
- `LaunchEnv/` — per-bottle environment files consumed by `Wine.app`
- `ScotchSettings.plist`, `BottleVM.plist`

Legacy `~/Library/Containers/com.s3brr.Scotch` and `~/Library/Logs/com.s3brr.Scotch` are read on first launch after 1.1.0 and copied into Application Support. Runtime reinstall replaces only `Libraries/`, never bottles or settings.

Bootstrap assets are fixed in `RuntimeAssets`: Wine Staging **11.16**, DXVK-macOS **1.10.3-repack**, DXMT **0.80 builtin**, GPTK **3.0-3**, and Mesa Windows **26.2.0**. Every package has exact size/SHA256 pins. `MetalEngineInstallation` supplies WineForge **0.6.0.3 / Wine 11.16** for every backend, with native support profile 2 and a Steam CEF-only DXMT loader policy. The original Gcenx Wine archive remains available for repair provenance. DXVK launches force Wine's builtin DXGI adapter enumeration through Vulkan to avoid its deprecated CGL path. Mono and Gecko remain local. The complete Apple framework/bridge is retained; builtin selection prevents silent renderer fallback.

`GraphicsSupportInstallation` verifies a bundled native support profile: MoltenVK **1.4.2**, x86_64 Mesa KosmicKrisp, per-instance Vulkan routing, and Vulkan-enabled Wine Unix modules with the 32-bit properties conversion fix. Zink receives KosmicKrisp while other Vulkan instances receive MoltenVK, including when both appear in one process. Native modules target macOS 26 and use portable dependencies. The source recipe, patches, hashes, licenses and complete corresponding sources ship with the DMG. The old 11.6 WineMac byte patch is not applied to Wine 11.16.

`RuntimeUpdateService` authenticates a signed feed, downloads/stages verified immutable sets under `RuntimeSets/ID`, and atomically selects the new default. Existing bottles pin legacy or their selected ID. Legacy graphics repair clones Libraries, repairs/verifies the complete stack and atomically exchanges it. Required failures preserve the old installation; bootstrap Apple-payload failure can leave the other backends available. DXMT's engine does not depend on that optional payload.

`ScotchAppUpdater` coordinates the single Update flow with app-only Sparkle. App replacement authenticates the feed/archive, backs up metadata, and resumes runtime checks after relaunch. `UpdateActivity` and an installation lock gate concurrent app/runtime/bottle operations. Wine-engine and runtime changes require idle processes and a complete recoverable prefix snapshot; `.ScotchWineEngine` protects first adoption of older Metal-selected prefixes too. Future/corrupt metadata and offline external catalog entries are preserved.

Uninstall (`Settings → Uninstall Scotch`, or `scotch uninstall --all`) kills Wine, then deletes the Application Support tree, leftover Containers/Logs folders, caches, CLI symlink, GPU spoof log, recorded shortcuts, and optionally bottles plus `Scotch.app`. Extra paths (custom bottle folders, desktop shortcuts, CLI) are appended to `InstallLedger.plist` as they are created. See `Docs/install_locations.md`.

## Compatibility strategy
- Keep bottle metadata shape stable (`Metadata.plist`).
- Preserve backend/env assembly behavior for DXVK, DXMT, D3DMetal, Zink, sync modes, and GPU spoofing keys.
- Launch via `open -a Wine.app --args start /unix ...` so Wine's child processes get a proper foreground activation policy.

## Performance strategy
- IO/process work is off main actor.
- Bottle scans are explicit refresh actions and run in background tasks.
- Logging uses append-only file handles with deterministic locations.
