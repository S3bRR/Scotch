# Scotch

A native macOS app for running Windows games and applications on Apple Silicon.

Scotch targets **macOS 26 Tahoe** and **Apple Silicon (M-series)**. It wraps an up-to-date Wine Staging build with DX11/12 translation via Apple's D3DMetal, DX9–11 via DXVK, native-Metal D3D10/11 via 3Shain's DXMT, and OpenGL via Mesa Zink — each selectable per bottle.

This is a personal project. Use at your own risk.

## Download & Install

**[Download the latest release here](https://github.com/S3bRR/Scotch/releases)**

1. Download the `.dmg` file from the latest release
2. Open the `.dmg` and drag **Scotch** into your **Applications** folder
3. On first launch, macOS will warn that the app is from an unidentified developer — right-click the app, click **Open**, then confirm

Scotch will download Wine, DXVK, DXMT, and the other backends automatically on first run (~500 MB).

## What Scotch is built from

Scotch is a native SwiftUI shell around other people's hard work. The app itself handles bottle management, the setup wizard, config, launch orchestration, and a bit of binary-patching — the compatibility comes from these upstream projects:

| Component | Project | What it does |
|---|---|---|
| Core compatibility layer | **[Wine](https://www.winehq.org/)** (via [Gcenx's macOS builds](https://github.com/Gcenx/macOS_Wine_builds) of Wine Staging 11.6) | Translates Win32 API calls to macOS equivalents. Everything else on this list sits on top of Wine. |
| DirectX 9/10/11 → Vulkan → Metal | **[DXVK](https://github.com/Gcenx/DXVK-macOS)** (Gcenx's macOS port of [doitsujin/dxvk](https://github.com/doitsujin/dxvk)) + **[MoltenVK](https://github.com/KhronosGroup/MoltenVK)** | Widest compatibility path. Default backend for new bottles. |
| DirectX 10/11 → Metal (native) | **[DXMT](https://github.com/3Shain/dxmt)** by 3Shain | Native-Metal alternative for D3D11 titles. Better Apple Silicon perf than DXVK for the games it supports. |
| DirectX 11/12 → Metal (native) | **[D3DMetal](https://developer.apple.com/games/game-porting-toolkit/)** from Apple's Game Porting Toolkit 3 | Apple's own DX11/12 translation layer. Required for DX12 titles. |
| OpenGL 4.6 → Vulkan → Metal | **[Mesa Zink](https://docs.mesa3d.org/drivers/zink.html)** (Windows build by [pal1000](https://github.com/pal1000/mesa-dist-win)) | Works around macOS 26's OpenGL deprecation by sidestepping Apple's CGL entirely. |
| UI framework | **SwiftUI** | Native macOS interface. |

Each translation backend is a separate option in the bottle config picker. You pick one per bottle based on the game's needs.

## Features

- **DXVK / DXMT / D3DMetal / Zink** translation backends, selectable per bottle.
- **GPU identity spoofing**: Four-layer spoof so games detect a known NVIDIA/AMD GPU instead of Apple Silicon (vendor `0x106b`). Combines a Vulkan shim that patches `vkGetPhysicalDeviceProperties` at runtime, `dxvk.conf` generation, Wine Direct3D registry keys, and MoltenVK compatibility vars. Preset picker with AMD RX 7900 XTX, RX 6800 XT, NVIDIA RTX 4090, RTX 3080, Custom, and Off.
- **Additive Zink toggle** for titles that need OpenGL 4.6.
- **Winetricks** integrated as a sheet; first-run `corefonts` bootstrap.
- **Diagnostics screen** with live process list, log browser, and effective-environment preview.
- **Start-menu discovery** that auto-pins `.lnk`-discovered programs per bottle.
- **Per-program settings** (locale, arguments, env vars) persisted alongside the bottle.
- **QuickLook** thumbnails for `.exe` files in Finder.
- **CLI tool** (`scotch`) for `list`/`run`/`add`/`remove`/`shellenv` operations.

## System requirements

- **macOS 26 Tahoe** or later
- **Apple Silicon** (M1 / M2 / M3 / M4 / M5 / Pro / Max / Ultra)
- **Rosetta 2** installed (Wine runs under Rosetta — Scotch will prompt during setup if missing)
- ~500 MB of free disk for the Wine runtime + overlays; additional space per bottle for your Windows installs

## Tested matrix

| Component | Version | Source |
|-----------|---------|--------|
| Wine | 11.6 | Gcenx/macOS_Wine_builds (latest) |
| DXVK | 1.10.3 | Gcenx/DXVK-macOS (latest) |
| DXMT | 0.74 | 3Shain/dxmt (latest) |
| D3DMetal | 3.0 | Apple GPTK 3 (Scotch overlay) |
| Mesa Zink | 24.3.4 | pal1000/mesa-dist-win, repackaged in Scotch `zink-1.0` |
| MoltenVK | 1.4.1 | Bundled with Gcenx Wine |
| macOS | 26 | Tahoe minimum, Apple Silicon only |

Other combinations may work but are unsupported.

## How it works

1. On first run, Scotch downloads Wine Staging 11.6 + DXVK + DXMT from their upstream GitHub releases.
2. It downloads three Scotch-hosted overlays on top of that:
   - A pre-patched `winemac.so` that enables OpenGL 3.2+ Core Profile context creation (a byte-level patch that works around a hardcoded rejection in Wine 11.6).
   - Apple's D3DMetal 3.0 framework (redistributed from GPTK 3 for DX11/12 support).
   - Mesa Zink for OpenGL-over-Vulkan.
3. It builds a `Wine.app` launcher bundle so Wine's child processes get a proper macOS foreground activation policy — without this, Wine's windows are created invisible offscreen.
4. When you create a bottle, Scotch creates a Wine prefix and runs `wineboot --init` to set up the Windows environment.
5. When you run an `.exe`, Scotch copies the backend-specific DLLs (DXVK / DXMT / D3DMetal / Zink) into the bottle's `system32` and `syswow64`, sets the right `WINEDLLOVERRIDES`, and launches Wine via the `Wine.app` wrapper.

## Not supported

- **Anti-cheat games** (Easy Anti-Cheat, BattlEye, Vanguard, Ricochet). These look for specific kernel hooks that don't exist on Wine. No translation layer fixes them.
- **Intel Macs**. Scotch targets Apple Silicon exclusively.
- **macOS older than 26**. The deployment target is Tahoe; some code paths depend on Tahoe-era frameworks.
- **Auto-updates**. Not wired up.

## Credits and thanks

Scotch is a thin SwiftUI layer over other people's hard work. All of the following deserve the credit for the parts that make Scotch actually do anything useful; I only wrote the glue.

### First and foremost: Wine

The entire Windows compatibility layer is [Wine](https://www.winehq.org/). Two decades of work by hundreds of contributors went into making Win32 apps run on non-Windows systems. Scotch ships a Wine distribution that shouldn't be mistaken for original work — it's Wine doing the heavy lifting, with Scotch providing the macOS integration shell.

- **The Wine project** (https://www.winehq.org/) and its contributors.
- **[CodeWeavers](https://www.codeweavers.com/)** for WineCX and CrossOver, which provide many of the macOS-specific patches that Scotch inherits through Gcenx's builds. CrossOver is the paid, supported, actively developed path for Windows-on-Mac — please consider [supporting them](https://www.codeweavers.com/store).
- **[Gcenx](https://github.com/Gcenx)** for maintaining the macOS Wine builds that Scotch downloads at setup (`Gcenx/macOS_Wine_builds`), the macOS port of DXVK (`Gcenx/DXVK-macOS`), and the Homebrew cask for Apple's Game Porting Toolkit.

### Translation layers

- **[doitsujin](https://github.com/doitsujin)** for DXVK, the best open-source DX→Vulkan translator.
- **[3Shain](https://github.com/3Shain)** for DXMT, a newer native-Metal D3D10/11 implementation.
- **Apple** for the [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/), D3DMetal, and the Metal framework itself. D3DMetal 3.0 is redistributed here under the terms of Apple's GPTK Beta License; removal on request.
- **The [Mesa 3D](https://www.mesa3d.org/) project** and its contributors for Gallium, the Zink driver, and the OpenGL 4.6 implementation.
- **[pal1000](https://github.com/pal1000)** for [mesa-dist-win](https://github.com/pal1000/mesa-dist-win), the Windows builds of Mesa that make Zink usable from a Wine prefix.
- **[KhronosGroup](https://github.com/KhronosGroup)** for MoltenVK, the Vulkan-over-Metal shim that underpins both DXVK and Zink on Apple Silicon.
- **[Moonshine](https://github.com/ybmeng/moonshine)** for figuring out the `winemac.so` OpenGL patch approach that Scotch's overlay is derived from.

### Other dependencies

- **[msync](https://github.com/marzent/wine-msync)** by marzent — synchronization primitives available through Wine under macOS.

### Community

Thanks to everyone on the Wine, CrossOver, and Moonshine forums / issue trackers for documenting the obscure byte offsets, registry keys, and `WINEDLLOVERRIDES` recipes that make this kind of thing work.

## License

Scotch is [GPL-3.0](./LICENSE), inherited from Wine. All included third-party code retains its original license. See:

- `LICENSE` — the GPL-3 that covers Scotch's Swift source
- Wine, DXVK, DXMT, Mesa, Zink — each under their respective upstream licenses
- D3DMetal — Apple's GPTK Beta License (redistributed; removal on request)
