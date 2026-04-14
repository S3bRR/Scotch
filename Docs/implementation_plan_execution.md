# Scotch V2 Parity Implementation Plan (Execution Tracker)

This document is the active execution tracker for the parity directive.

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Implemented + verified in code/tests/docs
- [!] Deferred with explicit rationale

## Phase 0: Scope and Parity Contract
- [x] Build canonical feature matrix from legacy Scotch sources and README.
- [x] Mark each feature as Required / Optional / Intentional Change.
- [x] Freeze matrix in `scotch_v2/Docs/parity_matrix.md`.
- [x] Add owner/status/acceptance columns.
- [x] Add no-silent-regression policy.
- [x] Add definition-of-done per feature (UI/runtime/tests).
- [x] Add migration compatibility section.
- [x] Use this tracker as the approved execution contract.

## Phase 1: Data and Migration Safety
- [x] Keep BottleVM.plist + BottleCatalog.plist dual-read support.
- [x] Keep legacy paths + new bottlePaths dual-encoding.
- [x] Keep legacy Metadata.plist key compatibility (`wineConfig`, `metalConfig`, `backendConfig`, `dxvkConfig`, `gpuConfig`).
- [x] Keep legacy enum-object decoding (`dxvkHud`, `enhancedSync`).
- [x] Add decode fixtures for legacy payloads.
- [x] Add tests for legacy read -> V2 write -> re-read compatibility.
- [x] Add migration fallback telemetry/log entries.
- [x] Add hard-fail alert path for corrupted metadata decode.
- [x] Add integration test loading a realistic old bottle tree fixture.
- [x] Add migration report output in diagnostics view.

## Phase 2: Winetricks and First-Run Parity
- [x] Implement `WinetricksService` in ScotchRuntime.
- [x] Add `ensureInstalled` from official Winetricks script URL.
- [x] Add bundled `cabextract` strategy or explicit dependency path handling.
- [x] Add headless execution with deadlock-safe stdout/stderr handling.
- [x] Add verb parser (`list-all`) and category model.
- [x] Add interactive Terminal-run mode parity.
- [x] Add Winetricks UI sheet in bottle tools.
- [x] Wire bottle creation flow to best-effort corefonts bootstrap.
- [x] Add error surfacing and retry behavior.
- [x] Add tests for parser/env/failure handling.

## Phase 3: Advanced Config Parity
- [x] Add build version read/write registry support.
- [x] Add Retina mode read/write support.
- [x] Add DPI query/update support (with preview sheet).
- [x] Add config actions: `control`, `regedit`, `winecfg`.
- [x] Keep GPU spoof + backend toggles operational.
- [x] Revalidate `steamBuiltinOpenGL` + Zink interactions after config additions.
- [x] Add on-change sync parity for settings that require immediate registry sync.
- [x] Add config regression tests against temp bottle.
- [x] Add UI save/apply behavior coverage.
- [x] Add diagnostics action to print effective bottle config.

## Phase 4: Program Model and Launch Parity
- [x] Add per-program settings store in `Program Settings/*.plist`.
- [x] Implement locale selection with stable enum set.
- [x] Implement per-program launch arguments string + parser.
- [x] Implement per-program custom env vars.
- [x] Apply per-program settings in `runProgram` path.
- [x] Add program detail/config screen.
- [x] Add shift-run/terminal-run equivalent (or documented replacement).
- [x] Keep pin/blocklist operations available.
- [x] Add tests for argument parsing + env precedence.
- [x] Add tests for program settings persistence roundtrip.

## Phase 5: Program Discovery and Start Menu Parity
- [x] Port `.lnk` parsing for start-menu discovery.
- [x] Scan global and user start-menu paths.
- [x] Convert discovered links into program entries.
- [x] Auto-pin discovered items for parity.
- [x] Keep duplicate suppression logic.
- [x] Keep stale-pin cleanup behavior.
- [x] Validate case-insensitive path matching behavior.
- [x] Add tests with `.lnk` fixture(s).
- [x] Add runtime logs for discovery actions.
- [x] Add UI indicator for start-menu-discovered items.

## Phase 6: Bottle Management Parity
- [x] Add rename bottle action in sidebar context menu.
- [x] Add move bottle action with pin/blocklist path rewrite.
- [x] Add export bottle as tar archive.
- [x] Add import/open existing bottle action.
- [x] Keep remove-from-list vs delete-files confirmation flow.
- [x] Add state refresh consistency after management operations.
- [x] Add tests for move + path rewrite behavior.
- [x] Add tests for export/import roundtrip.
- [x] Add rollback behavior for partial failures.
- [x] Add diagnostics for orphaned catalog entries.

## Phase 7: App-Level Behavior Parity
- [x] Implement app command menu parity (open setup/logs/kill/open-existing).
- [x] Wire kill-on-exit app setting to termination behavior.
- [x] Wire runtime update-check setting to update-check flow.
- [x] Add old-log pruning policy on startup.
- [x] Add clear-shader-cache action.
- [x] Keep external open path single-window safe.
- [x] Keep one-bottle vs multi-bottle open handling.
- [x] Add app lifecycle hook(s) equivalent to old AppDelegate behavior.
- [x] Add settings migration for old defaults keys.
- [x] Add smoke tests for command handlers.

## Phase 8: Runtime Download and Install Hardening
- [x] Add explicit prerelease/draft safeguards around release discovery.
- [x] Add retries + backoff for downloads.
- [x] Add checksum support when available.
- [x] Split error classes: discovery/download/extract/install.
- [x] Add partial-install rollback/resume strategy.
- [x] Keep overlay versions centralized.
- [x] Add runtime manifest sanity checks.
- [x] Add disk-space preflight checks.
- [x] Add post-install verification checks.
- [x] Add repair-install action in setup UI.

## Phase 9: Target and Packaging Parity
- [x] Decide strict CLI parity requirement.
- [x] Add ScotchCmd + shellenv behavior target.
- [x] Add CLI install/uninstall flow parity.
- [x] Decide thumbnail parity requirement.
- [x] Add thumbnail target + icon extraction helper.
- [x] Add packaging script parity (DMG/resource placement) if required.
- [x] Ensure `cabextract`/shim artifacts in release packaging if required.
- [x] Validate entitlements + Apple Events strings for final app bundle.
- [x] Validate bundle resources across architectures.
- [x] Add notarization/signing checklist for releases.

## Phase 10: Validation and Release Gating
- [x] Expand test suite for parity-critical behavior.
- [x] Add end-to-end tests (creation/launch/msi/bat/steam).
- [x] Add path-with-spaces and unicode-path tests.
- [x] Update real-bottle validation script for new features.
- [x] Maintain manual QA matrix pass/fail per feature.
- [x] Add startup/refresh/launch performance checks.
- [x] Enforce release gate: required features complete or explicitly waived.
- [x] Emit final parity report (preserved/intentional changes/gaps).
- [x] Run acceptance pass on real bottle dataset and record results in `Docs/manual_validation_report.md` (PASS=12, FAIL=0, SKIP=2 on 2026-04-13).
- [x] Enforce release-tag gating in `scripts/release_gate.sh` and `Docs/release_checklist.md`; perform tagging only after checks pass.

## Current Execution Focus
- [x] Phase 2 (Winetricks/corefonts)
- [x] Phase 4 + 5 (program settings + start menu parity)
- [x] Phase 3 (advanced config runtime/UI)
- [x] Phase 6 + 7 (management/app command parity)
- [x] Phase 8 hardening quick wins
- [x] Phase 9 packaging/release tooling
- [x] Phase 10 validation/release gating

## Phase 11: macOS 26 (Tahoe) Hardening Pass — 2026-04-14
Targeted three concrete risks discovered in a pre-Tahoe audit (main-actor blocking,
download reliability, and Tahoe-relevant AppKit anti-patterns).

- [x] **ProcessRunner**: added optional `timeout` to `ProcessSpecification` with SIGTERM →
  SIGKILL escalation. `captureProcess` surfaces a typed `ProcessRunnerError.timeout`. Added
  non-blocking pipe drain in the termination handler so short-lived processes no longer drop
  their final stdout chunk.
- [x] **NetworkClient abstraction**: introduced `NetworkClient` protocol +
  `DefaultNetworkClient` in `ScotchInfrastructure/Network`. Configures `URLSession` with
  explicit `timeoutIntervalForRequest`/`timeoutIntervalForResource`, applies a default
  User-Agent, and retries idempotent transport failures and 5xx/429 with quadratic backoff
  matching the previous inline retry shape.
- [x] **Main-actor fixes**:
  - `AppViewModel.clearShaderCaches` rewritten as `async`, routes through `ProcessRunner`,
    moves the `FileManager.removeItem` off the main actor.
  - `ScotchAppDelegate` replaces the `DispatchSemaphore.wait()` bridge with
    `applicationShouldTerminate` + `.terminateLater` + 3.5 s ceiling. Termination cleanup
    extracted to `ScotchContainer.performTerminationCleanup(deadline:)` for unit testing.
- [x] **Process() migrations** (7 sites): `BottleRepository.exportBottle`,
  `TarArchive.extract`, `RuntimeInstallerService.buildGPUSpoofShim`,
  `RosettaService.installIfNeeded`, `WinetricksService.runHeadless` and `runInTerminal`,
  and `ScotchCmd/main.swift`. Deleted `LockedData`/`AtomicFlag`/`TimeoutFlag` helpers from
  `WinetricksService`. `ScotchCmd` now uses `async main()` + the canonical `ProcessRunner`.
- [x] **URLSession.shared migrations** (6 sites): `RuntimeInstallerService` (4 sites),
  `WinetricksService.ensureInstalled`, `BottleDetailViewModel.installSteam`. Inline retry
  blocks deleted; retry now centralized in the client.
- [x] **SwiftUI-native dialogs**: 6 `NSOpenPanel.runModal()` migrated to
  `.fileImporter(...)` (BottleDetailView Run File / Add Pin, RootView Open Existing /
  Move, BottleCreationSheet Browse, SettingsPanelView Browse). 2 `NSSavePanel.runModal()`
  migrated to a new `AsyncSavePanel` helper that wraps `NSSavePanel.begin(_:)` in a
  continuation. Rename uses `.alert` + `TextField`; delete uses `.confirmationDialog`.
  `CommandLineInstaller.install()` now returns `Result<Void, CLIInstallError>` and routes
  outcomes through `viewModel.toastMessage` via a notification.
- [x] Documented `DefaultProcessRunner: @unchecked Sendable` rationale.

### Tests added (25)
| Target | New cases |
|---|---|
| `ScotchRuntimeTests` | `ProcessRunnerTimeoutTests` (4), `NetworkClientTests` (9), `TarArchiveTests` (2), `WinetricksServiceTimeoutTests` (2), `WinetricksEnsureInstalledTests` (2) |
| `ScotchFeaturesTests` | `TerminationCleanupTests` (3), `SteamInstallTests` (2), `BottleDetailViewModelRenameTests` (2) |

Test count: 39 (baseline) → 65. `swift build`, `swift test` clean.

### Grep gates (zero matches in `Sources/`)
- `URLSession.shared` — 0
- `DispatchSemaphore` — 0
- `readDataToEndOfFile` — 0
- `waitUntilExit` — 0
- `NSAlert()` — 0
- `.runModal()` — 0 (only the docstring reference inside `AsyncSavePanel.swift` remains)
- raw `Process()` outside `ProcessRunner.swift` — 0

### Out of scope / known gaps
- `LogStore.String(contentsOf:)` left blocking; current log sizes are small enough.
- `Info.plist` `LSMinimumSystemVersion` is still `14.0` while `Package.swift` targets `.v26`
  — bump is a separate decision.
- `NSAppleEventsUsageDescription` already present; Tahoe will prompt for Automation
  permission on first Winetricks "Run in Terminal" use and on first CLI installer use.
  Manual QA checklist updated.
- `ScotchCmdExecutionTests` and `CommandLineInstallerResultTests` were planned but skipped
  because the `ScotchCmd` and `ScotchApp` targets are executables, not testable libraries.
  Verifying these end-to-end requires either splitting them into library targets or running
  the built binaries — both are larger structural changes than this hardening pass should
  carry. Manual QA covers both flows.
