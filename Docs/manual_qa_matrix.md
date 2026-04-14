# Scotch V2 Manual QA Matrix

## Scope
Manual verification matrix for parity-critical user flows. Keep this table updated per release candidate.

| Feature | Required | Last Result | Evidence |
|---|---|---|---|
| Runtime setup (Rosetta + Wine/DXVK/DXMT + overlays) | Yes | PASS | `Docs/manual_validation_report.md` |
| Bottle create + first-run bootstrap (`wineboot`, `winecfg`, corefonts) | Yes | PASS | `RuntimeParitySmokeTests.bottleCreationRunsWineBootWinecfgAndCorefonts` |
| External launch (`.exe`, `.msi`, `.bat`) | Yes | PASS | `RuntimeParitySmokeTests.launchFlowSupportsExeMsiBatSteamAndUnicodePaths` |
| Steam launch path discovery | Yes | PASS | `RuntimeParitySmokeTests.launchFlowSupportsExeMsiBatSteamAndUnicodePaths` |
| Program list pin/blocklist flows | Yes | PASS | `BottleDetailAndAppCommandTests` + manual spot-check |
| Config apply/save (Windows version + compatibility sync) | Yes | PASS | `BottleDetailAndAppCommandTests` |
| Start-menu discovery and pinning | Yes | PASS | `ShellLinkParserTests` + repository discovery tests |
| Bottle management (rename/move/export/import/delete) | Yes | PASS | `BottleRepositoryProgramSettingsTests` |
| App command handlers (kill bottles/open setup/open logs/open existing/clear shader cache) | Yes | PASS | `BottleDetailAndAppCommandTests.killAllBottlesCommandSignalsEveryBottle` + app command wiring review |
| Migration compatibility (legacy catalog/metadata/pins/blocklist/defaults) | Yes | PASS | `BottleCompatibilityTests` + `AppSettingsCompatibilityTests` |
| GPU spoof + Zink/Steam override compatibility behavior | Yes | PASS | `EnvironmentAssemblerTests` + runtime sync code path |

## Tahoe-specific manual QA (added 2026-04-14)

| Flow | Expected behavior |
|---|---|
| Menu → Clear Shader Cache | Toast appears within ~1 s; UI stays responsive while a populated `d3dm` directory is removed. |
| Cmd-Q with "Kill processes on terminate" enabled | App exits within ~4 s even if wine processes are slow to die (3.5 s cleanup ceiling). |
| Run File / Add Pin / Open Existing Bottle / Move / Browse default location / Browse bottle creation location | SwiftUI `.fileImporter` opens, returns the selected URL, no UI freeze. |
| Export bottle, Create shortcut | `AsyncSavePanel` opens (NSSavePanel via `begin(_:)`), returns the chosen URL, no UI freeze. |
| Rename bottle from sidebar | `.alert` with text field; renames on Enter. |
| Delete bottle from sidebar | `.confirmationDialog` with destructive button; cancel does nothing. |
| Install Command Line Tool | Admin prompt appears; success or error surfaces as a toast (no NSAlert). |
| First-run Winetricks "Run in Terminal" | Tahoe prompts for Automation permission against Terminal — accept once. |
| Steam install on a fresh bottle | Installer downloads and runs; transport failure surfaces as a status message rather than a hang (no `URLSession.shared`). |

## Notes
- When a real local bottle dataset is unavailable, rely on automated parity smoke tests and mark user-data-dependent checks as `N/A` in release notes.
- Update this file whenever release-candidate validation is rerun.
