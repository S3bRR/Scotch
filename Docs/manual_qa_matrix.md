# Scotch Manual QA Matrix

Manual verification matrix for release-candidate flows. Update per release.

## Core flows

| Flow | Expected behavior |
|---|---|
| Runtime setup (Rosetta + Wine/DXVK/DXMT + overlays) | First-run setup completes; runtime manifest written under Application Support. |
| Bottle create + first-run bootstrap (`wineboot`, `winecfg`, corefonts) | New bottle appears in sidebar with name; `drive_c` populated; Metadata.plist written. |
| External launch (`.exe`, `.msi`, `.bat`) | Finder double-click routes to Scotch; bottle picker appears when >1 bottle. |
| Steam launch path discovery | "Install Steam" completes; `Steam.exe` appears as a pinned program. |
| Program list pin/blocklist | Pins persist across relaunch; blocked items stay hidden from the programs list. |
| Config apply/save (Windows version + compatibility sync) | Windows version write triggers registry sync; backend change updates DLL overrides on next launch. |
| Start-menu discovery and pinning | `.lnk` items under `drive_c/users/Public/Start Menu` auto-pin per bottle. |
| Bottle management (rename/move/export/import/delete) | Rename updates sidebar + Metadata.plist; move rewrites pin/blocklist paths; export produces a tar archive that re-imports cleanly; delete removes all bottle files and kills running wine processes first. |
| App command handlers (kill bottles/open setup/open logs/open existing/clear shader cache) | Each command produces the expected side effect; toast confirms result. |
| GPU spoof + Zink/Steam override | Bottle launches with expected `DXVK_DEVICE_ID`/`DXVK_VENDOR_ID` env; Zink overlay mounts DLLs; Steam builtin OpenGL override applies when toggled. |

## Tahoe-specific flows

| Flow | Expected behavior |
|---|---|
| Menu → Clear Shader Cache | Toast appears within ~1 s; UI stays responsive while a populated `d3dm` directory is removed. |
| Cmd-Q with "Kill processes on terminate" enabled | App exits within ~4 s even if wine processes are slow to die (3.5 s cleanup ceiling). |
| Run File / Add Pin / Open Existing Bottle / Move / Browse default location / Browse bottle creation location | SwiftUI `.fileImporter` opens, returns the selected URL, no UI freeze. |
| Export bottle, Create shortcut | `AsyncSavePanel` opens (`NSSavePanel.begin(_:)`), returns the chosen URL, no UI freeze. |
| Rename bottle from sidebar | `.alert` with text field; renames on Enter. |
| Delete bottle from sidebar | `.confirmationDialog` with destructive button; cancel does nothing. |
| Install Command Line Tool | Admin prompt appears; success or error surfaces as a toast. |
| First-run Winetricks "Run in Terminal" | Tahoe prompts for Automation permission against Terminal — accept once. |
| Steam install on a fresh bottle | Installer downloads and runs; transport failure surfaces as a status message rather than a hang. |
