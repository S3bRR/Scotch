# Scotch V2 Final Parity Report

## Preserved Behavior
- Legacy bottle catalog + metadata compatibility (including older key/enum/path variants).
- Runtime installation and launch pipeline (Wine/DXVK/DXMT + overlays via `open -a Wine.app --args start /unix ...`).
- Compatibility behavior for DXVK/Zink/Steam OpenGL override and GPU spoof registry/env assembly.
- Winetricks integration with first-run `corefonts` bootstrap path.
- Program discovery + per-program settings + blocklist/pin operations.
- Bottle management parity (rename/move/export/import/remove/delete confirmation behavior).
- App-level commands and lifecycle parity (single-window file-open handling, kill-on-exit).
- CLI target (`ScotchCmd`) and thumbnail helper target (`ScotchThumbnail`).

## Intentional Changes
- Modularized architecture split (`ScotchDomain`, `ScotchInfrastructure`, `ScotchRuntime`, `ScotchFeatures`).
- Updated UX/theme while preserving capability parity.
- Added explicit hardening around release discovery, download retry/backoff, checksum verification, and post-install checks.
- Runtime installation is now strict: overlay failures (winemac/D3DMetal/Zink) hard-fail install and trigger rollback.

## Validation Evidence
- Automated tests: `swift test` (39 tests / 13 suites passing).
- Build verification: `swift build --product ScotchApp` and `swift build --product ScotchCmd` pass.
- App metadata verification: `NSAppleEventsUsageDescription` is present in `Sources/ScotchApp/Info.plist`.
- Manual/diagnostic artifacts:
  - `Docs/manual_validation_report.md`
  - `Docs/manual_qa_matrix.md`
  - `Docs/performance_smoke_report.md` (generated via `scripts/performance_smoke.sh`)

## Residual Risk / Waivers
- Release tagging/notarization remains a release-operator action and is documented in the release checklist.
