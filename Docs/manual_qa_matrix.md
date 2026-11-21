# Scotch Manual QA Matrix

Manual verification matrix for release-candidate flows. Update per release.

## Core flows

| Flow | Expected behavior |
|---|---|
| Runtime setup (Rosetta + Wine/DXVK/DXMT + overlays) | First-run setup completes; runtime manifest written under Application Support. |
| D3DMetal overlay unavailable (404 or malformed archive) | Setup completes with a warning; Zink, DXVK, and DXMT remain usable. Restart does not reopen setup. D3DMetal is absent from the backend picker on a fresh install. |
| Reinstall while D3DMetal download is unavailable | A verified existing D3DMetal is preserved; an incomplete old overlay is not marked installed. |
| Upstream Zink install | SHA256 is checked; both `Zink/x64` and `Zink/x32` contain `opengl32.dll` and `libgallium_wgl.dll`. Mesa's D3D/Vulkan drivers are not injected. A failed download, checksum, or required DLL verification rolls back the runtime. |
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
| Settings → Uninstall Scotch | Preview lists runtime, logs, caches, CLI, leftover folders; optional bottle/app removal; after confirm those paths are gone and the app quits. |
| `scotch uninstall --all` | Same cleanup from the CLI without leaving `~/Library/Application Support/com.s3brr.Scotch` or `/usr/local/bin/scotch`. |
| First-run Winetricks "Run in Terminal" | Tahoe prompts for Automation permission against Terminal — accept once. |
| Steam install on a fresh bottle | Installer finishes before Steam is pinned/launched; client updates reach sign-in without a runtime switch. The native CEF bridge is available on the first launch with GPU compositing enabled. Timeouts and transport failures preserve the bottle. |

| Flow | Expected result |
| --- | --- |
| Unified Update | One Update action reports both app/runtime status and applies eligible changes; no separate runtime/app install buttons. |
| Existing bottles after runtime update | Existing runtime selections and registry/save files remain unchanged; new bottles use the new default. |
| Runtime switch and restore | Full snapshot precedes a switch; Restore Last Snapshot recovers the prior prefix and keeps the replaced data. |
| App replacement | Signed local/released update preserves data, replaces the app, relaunches, and no longer offers the same build. |
| Active game or bottle operation during Update | Installation waits; no updater-triggered game termination. Cancel remains available before activation. |

| Flow | Expected result |
| --- | --- |
| Build 12 graphics download and loader | No request to the removed Scotch overlay. GPTK, WineForge, DXMT, Wine, DXVK and Mesa pass exact size/SHA256 checks. D3DMetal uses the real Apple framework, DXMT the builtin winemetal bridge; no silent WineD3D fallback. |
| Existing core runtime repair | Update repairs the complete stack even before Pages feeds are published. Core Wine and user prefixes are retained; damaged WineMac/native modules are replaced from verified sources. Successful repair clears the notice after restart. |
| Adopt the matched engine | Close Wine processes; a complete prefix snapshot precedes first use, including legacy bottles already set to Metal. Wine, wineserver, Wine.app, CLI and winetricks agree on the engine. Restore recovers the prior backend and saves. |
| Zink GL 4.5+ | Actual OpenGL context and GPU readback, compute/DSA, RGB32 texel buffers, transform feedback and SwapBuffers pass in 32/64-bit processes. No GL version override. |
| Direct3D plus additive Zink | DXVK and DXMT pass combined 32/64-bit render/present; D3DMetal passes x64. Instance-specific Vulkan routing preserves both renderers. |
| Native module portability | Fresh/relocated installation needs no system Vulkan SDK or Homebrew dylibs; macOS 26 deployment target and source archive are checked. |

Hardware probes cover an M5 Pro on macOS 27.2.1. Test the reported OpenGL game,
Steam flows, other Mac generations, and minimum macOS manually before public
promotion. Passing synthetic rendering does not establish every game's support.

| Flow | Expected result |
| --- | --- |
| Build 13 Steam recovery | Existing legacy shim restores its saved vendor helper; an updated vendor helper remains untouched. Missing originals are recovered by Steam bootstrap. |
| Steam after a backend change | DXVK, DXMT and D3DMetal reach sign-in without a CEF GPU or sandbox breakpoint loop. Game arguments/backend remain unchanged. |

| Flow | Expected result |
| --- | --- |
| Build 14 Auto | Unambiguous x64 D3D12 and OpenGL programs resolve before launch; ambiguous APIs and launchers retain the bottle setting. Missing runtimes leave profiles/data intact. |
| Remember working setup | Startup alone records no confirmation. Explicit confirmation is reused only for matching application/runtime/launch settings; manual overrides win. |
| Shared backend changes | Running Wine/Windows processes, including orphaned .exe processes, block changes. Snapshot completes before activation and launch lease transfer. |
| Fresh Steam native UI | Both winemetal PE stubs are registered, first bootstrap reaches sign-in with GPU compositing enabled, vendor helper remains intact, and the window paints. |
| Scoped Stop Bottle | Stops only processes whose kernel Wine prefix matches the selected bottle. Another bottle's process stays alive. |
| Bottle Runtime placement | CPU button is in the bottom toolbar; no button sits between the Backend and Programs/Configuration cards. |

| Flow | Expected result |
| --- | --- |
| Build 15 Windows 11 fonts | Full bottle creation installs all ten core font families with bundled cabextract under Finder's minimal PATH; no Homebrew dependency or missing-extractor warning. Retrying corefonts succeeds. |
| Main Backend | New bottles show D3DMetal (DX11/12). Auto is not offered in the bottle picker. Former Auto bottles show D3DMetal; explicit selections persist on relaunch. |
| Inheritance and migration | Programs with Use Bottle Setting inherit the selected renderer (D3DMetal by default); per-program overrides win. Old explicit bottle backends stay manual after upgrade. |
