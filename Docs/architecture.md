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
- `Libraries/` — Wine, DXVK, DXMT, D3DMetal, Zink, GPU spoof dylib, winetricks
- `Bottles/` — default prefixes
- `Logs/` — launch logs
- `WinetricksCache/` — font/verb downloads
- `LaunchEnv/` — per-bottle environment files consumed by `Wine.app`
- `ScotchSettings.plist`, `BottleVM.plist`

Legacy `~/Library/Containers/com.s3brr.Scotch` and `~/Library/Logs/com.s3brr.Scotch` are read on first launch after 1.1.0 and copied into Application Support. Runtime reinstall replaces only `Libraries/`, never bottles or settings.

Uninstall (`Settings → Uninstall Scotch`, or `scotch uninstall --all`) kills Wine, then deletes the Application Support tree, leftover Containers/Logs folders, caches, CLI symlink, GPU spoof log, and optionally bottles plus `Scotch.app`.

## Compatibility strategy
- Keep bottle metadata shape stable (`Metadata.plist`).
- Preserve backend/env assembly behavior for DXVK, DXMT, D3DMetal, Zink, sync modes, and GPU spoofing keys.
- Launch via `open -a Wine.app --args start /unix ...` so Wine's child processes get a proper foreground activation policy.

## Performance strategy
- IO/process work is off main actor.
- Bottle scans are explicit refresh actions and run in background tasks.
- Logging uses append-only file handles with deterministic locations.
