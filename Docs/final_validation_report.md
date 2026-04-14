# Scotch V2 Validation Report

## Preserved behavior (implemented)
- Bottle catalog persistence and metadata-driven bottle configuration.
- First-run dependency setup flow for Rosetta + runtime installation.
- Runtime release discovery/download/install pipeline for Wine, DXVK, DXMT, and overlays.
- Wine launch execution through `open -a Wine.app --args start /unix ...`.
- Compatibility environment assembly for backend overrides, sync modes, zink, and GPU spoof keys.
- Compatibility registry synchronization for zink/steam overrides and GPU identity keys before launch.
- Program discovery scan for bottle-installed executables and pin awareness.
- App settings persistence and runtime version display.
- Steam launch flow with bottle-local executable discovery.
- Shortcut generation is wired in bottle program actions.
- Diagnostics screen includes log browser, process list/kill controls, and environment preview.

## Intentional changes
- Replaced static/global managers with injected protocol-backed services and actor implementations.
- Split codebase into layered modules (`Domain`, `Infrastructure`, `Runtime`, `Features`, `App`).
- Introduced typed app path and persistence abstractions.
- Replaced UI styling with a lightweight lime-accent design system.

## Build and test evidence
- `swift build` passes in `scotch_v2`.
- `swift test` passes in `scotch_v2`.
- Added parity smoke coverage for bottle creation/bootstrap and EXE/MSI/BAT/Steam launch flows (`RuntimeParitySmokeTests`).
- Added config/app-command regression coverage (`BottleDetailAndAppCommandTests`).
- Added checksum parsing/hash coverage (`SHA256ChecksumTests`).
- Legacy-name scan across `scotch_v2` returns no matches.
- Real-bottle validation script exists at `scripts/validate_real_bottles.py`.
- Manual validation output generated at `Docs/manual_validation_report.md`.

## Known risks and remaining gaps
- Real-bottle validation now detects active local bottle data and passes runtime/bottle smoke checks (see `Docs/manual_validation_report.md`).
- End-to-end gameplay parity still depends on app-specific executable behavior beyond smoke-test scope.

## Tahoe hardening pass (2026-04-14)
- Risk #1: Main-actor `Process()` blocking + `DispatchSemaphore` bridges fixed in
  `AppViewModel.clearShaderCaches` (now `async`) and `ScotchAppDelegate` (now uses
  `applicationShouldTerminate` + `.terminateLater`).
- Risk #2: All 6 `URLSession.shared` call sites migrated to a new `NetworkClient`
  abstraction with explicit timeouts and centralized retry.
- Risk #3: 7 `Process()` bypasses migrated to the canonical `ProcessRunner` (now with
  optional timeout). 8 `runModal()` panels + 4 `NSAlert` dialogs migrated to SwiftUI
  `.fileImporter`/`.fileExporter`-style flows, `.alert`, and `.confirmationDialog`.
- Test count: 39 → 65 (`swift build` + `swift test` clean). Grep gates verify zero
  remaining `URLSession.shared`, `DispatchSemaphore`, `readDataToEndOfFile`,
  `waitUntilExit`, `NSAlert()`, or `runModal()` matches in `Sources/`.
- See `Docs/implementation_plan_execution.md` "Phase 11" for the full breakdown.
