# Scotch V2 Parity Matrix

## Contract
- No silent regressions: any omitted or changed legacy behavior must be explicitly documented as `Intentional Change` or `Deferred`.
- Required features must include UI/runtime wiring and at least one acceptance check (automated test or manual QA step).

## Definition of Done
A matrix row is Done only when all are true:
1. Runtime behavior implemented.
2. User-facing control/surface present where applicable.
3. Automated coverage exists, or a named manual QA step is added to validation docs.
4. Migration impact documented when legacy data/paths/settings are involved.

## Migration Compatibility Scope
- Legacy bottle catalogs (`BottleVM.plist`, `BottleCatalog.plist`, legacy `paths`) must remain readable.
- Legacy `Metadata.plist` keys and enum encodings must decode without silent corruption.
- Legacy pin/blocklist URL encoding forms must map to V2 path-based model.

## Matrix

| Feature | Category | Owner | Status | Acceptance Test / Check |
|---|---|---|---|---|
| Bottle catalog dual-read (`BottleVM.plist` + `BottleCatalog.plist`) | Required | Runtime | Done | `BottleCompatibilityTests.decodesLegacyBottleCatalogPayload` |
| Legacy metadata key compatibility | Required | Domain | Done | `BottleCompatibilityTests.decodesLegacyBottleSettingsPayload` |
| Legacy enum-object decode (`enhancedSync`, `dxvkHud`) | Required | Domain | Done | Existing compatibility tests |
| Runtime install (Wine/DXVK/DXMT + overlays) | Required | Runtime | Done | Manual setup flow + `swift test` baseline |
| Wine launch path via `open -a Wine.app --args start /unix` | Required | Runtime | Done | `WineRuntimeService.runProgram` inspection + smoke run |
| Environment assembly parity (DXVK/Zink/sync/GPU keys) | Required | Runtime | Done | `EnvironmentAssemblerTests.dxvkEnvironmentIncludesExpectedKeys` |
| GPU spoof shim install and env usage | Required | Runtime | Done | Runtime installer source + env assembler checks |
| Winetricks service + UI | Required | Runtime/Features | Done | `WinetricksServiceTests` + `WinetricksSheetView` wiring |
| Bottle creation corefonts bootstrap | Required | Runtime | Done | `BottleRepository.createBottle` calls `installCoreFonts` |
| Program settings persistence (`Program Settings/*.plist`) | Required | Runtime/Domain | Done | `BottleRepositoryProgramSettingsTests.programSettingsRoundtripPersistsToProgramSettingsFolder` |
| Per-program locale/args/env launch integration | Required | Runtime/Features | Done | `ProgramSettingsTests` + `BottleDetailViewModel.runProgram` |
| Start-menu `.lnk` discovery ingestion | Required | Runtime | Done | `ShellLinkParserTests` + repository start-menu scan |
| Advanced config (build version/retina/dpi) | Required | Runtime/Features | Done | `AdvancedConfigSheetView` + registry sync methods |
| Config actions (`control`, `regedit`, `winecfg`) | Required | Runtime/Features | Done | `AdvancedConfigSheetView` actions |
| Bottle rename/move/export/import parity | Required | Features/Runtime | Done | Sidebar actions + `moveBottleRewritesPinAndBlocklistPaths` |
| App commands (open logs, kill bottles, clear shader, open existing) | Required | App/Features | Done | `ScotchApp` command group + `RootView` notifications |
| Kill-on-exit setting wiring | Required | App | Done | `ScotchAppDelegate.applicationWillTerminate` |
| Runtime update-check policy wiring | Required | App/Runtime | Done | `AppViewModel.bootstrap` checks `checkRuntimeUpdates` |
| Download hardening (retry/backoff + prerelease guard) | Required | Runtime | Done | `RuntimeInstallerService` retry/backoff + preflight/verification |
| CLI parity target | Optional | Product | Done | `ScotchCmd` target in package + `shellenv`/run/list/add/remove/delete commands |
| QuickLook thumbnail parity | Optional | Product | Done | `ScotchThumbnail` target with executable icon extraction helper |
| Packaging script parity (DMG/release extras) | Optional | Release | Done | `scripts/package_release.sh` + `scripts/verify_release_bundle.sh` + `Docs/release_checklist.md` |
| Design system rewrite (lime accent + simplified UI) | Intentional Change | Features | Done | Existing V2 UI implementation |
| Layered architecture split (Domain/Infra/Runtime/Features) | Intentional Change | Core | Done | Module layout + package targets |
