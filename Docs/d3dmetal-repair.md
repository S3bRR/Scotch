# Graphics repair in 1.2.4 build 14

The old `S3bRR/Scotch/releases/download/d3dmetal-3.0/d3dmetal-3.0.tar.gz`
asset returns 404. Making that backend optional lets setup finish, but does not
restore the renderer. Build 12 replaces that URL and repairs the complete
compatible graphics stack through the existing Update command.

## Download and loader compatibility

D3DMetal comes from the pinned GPTK 3.0-3 release. Its original framework,
native bridge, x64 PE modules, symlinks, and notices stay together. The stock
Gcenx Wine 11.16 loader cannot satisfy those PE shims' old Unix-call ABI; a
native/builtin fallback can silently select WineD3D instead. Scotch therefore
uses WineForge 0.6.0.3's matched Wine 11.16 engine for D3DMetal and DXMT, and
explicit builtin DLL overrides. DXMT's builtin package is installed in its
canonical architecture directories and registered for builtin discovery,
including its additional winemetal module. The matched engine is independent
of the Apple payload, so DXMT does not depend on D3DMetal's download.

Wine, wineserver, Wine.app, CLI, terminal, and winetricks all select the same
engine for a bottle. The matched engine also receives Wine's pinned Mono and
Gecko packages, avoiding first-launch download dialogs. Build 14 uses that matched engine for DXVK and standalone Zink as well, with
native profile 2 and the Steam CEF-only loader policy. The original stock Wine
archive is preserved for repair provenance. Assets are pinned by exact HTTPS URL,
size, and SHA256; setup does not query a moving GitHub latest release.

## Vulkan and OpenGL

The previously bundled MoltenVK 1.4.0 failed 32-bit DXVK external-memory
allocation. The pinned 1.4.2 distribution passes the 32/64-bit render probes.
Wine's builtin DXGI also enumerates adapters through WineD3D, whose default
OpenGL path could enter Apple's deprecated CGL renderer before DXVK device
creation. Repeated mixed 64/32-bit starts exposed crashes and hangs there.
DXVK launches now explicitly use `WINE_D3D_CONFIG=renderer=vulkan`, including
Wine.app launches. Five cold 64-to-32-bit pairs then passed readback and
presentation, with their 32-bit processes avoiding CGL's GLEngine.
AppKit can load OpenGL independently in a 64-bit process; module presence alone
is not used as proof of the selected renderer. Increasing conversion arenas alone
did not resolve this separate path, so that experimental change was rejected.
Zink needs features that this MoltenVK still lacks. Substituting an installed
system Mesa or a Vulkan version string cannot supply those features inside
Wine.

Scotch now bundles a private x86_64 build of Mesa KosmicKrisp, targeting macOS
26. Its transform-feedback and RGB32 texel-buffer patches are confined to the
KosmicKrisp driver. A small native Vulkan router selects KosmicKrisp for Zink
instances and MoltenVK for other instances. Dispatch remains tied to the
actual instance/device, so Direct3D and OpenGL can coexist in one process.
The router exports the Metal surface function WineMac probes directly;
providing only vkGetInstanceProcAddr is insufficient for Wine's window path.
GPU identity overrides apply only to MoltenVK, preserving Zink's actual GPU
identity and driver workarounds.

The native Wine modules are rebuilt with Vulkan enabled. A WoW64 conversion
arena fix protects the two 32-bit physical-device-properties calls from an
inline-arena lifetime problem during GPU enumeration. All shipped dylibs use
relative loader paths and system dependencies; no Homebrew or separately
installed Vulkan SDK is needed at runtime. No OpenGL version is spoofed.

## Repair and data preservation

Update verifies the Metal engine, D3DMetal, DXMT, DXVK, Zink, native support
hashes, and stock WineMac driver. An old incorrect binary overlay is restored
from the pinned Wine archive. Repair copies Libraries into a private staging
area, installs and validates the complete replacement there, then atomically
exchanges directories. A failure before activation leaves the previous
Libraries intact. Cached archives are rehashed before reuse. The manifest and
repair state are recomputed, so a successful repair clears its banner.

This bootstrap repair works before the update feeds are deployed. Approved
runtime sets use the same validation and staged replacement. Existing bottles
retain their selected runtime set. Crossing Wine engines snapshots the full
prefix before its first use, including older bottles already configured for
a Metal backend. Explicit runtime switching and restore also retain recovery
copies beside the bottle on its own volume. No repair opens a user's prefix.
External symlink targets require their own backups.

## Verification

Run `bash scripts/test_live_runtime.sh .build/runtime-fixtures` on an idle test
Mac with Rosetta and mingw-w64. It uses a unique application ID, disposable
prefix, real release archives, and the shipping installer/launch services.
Its matrix checks:

- DXVK and DXMT: 32/64-bit D3D11 clear, GPU readback, and window presentation.
- D3DMetal: x64 D3D11 and D3D12 clear/readback, plus window presentation and
  proof that Apple's framework/native bridge loaded.
- Zink: 32/64-bit real OpenGL context, clear/readback/presentation, OpenGL 4.5
  DSA and compute, RGB32 texel-buffer fetch/size, and transform feedback.
- Direct3D plus additive Zink in one Windows process for all three backends.
- Wine.app GUI launches, install/repair, engine adoption, and save recovery.

The development hardware is an Apple M5 Pro running macOS 27.2.1. Standalone
Zink tests report OpenGL 4.6 core / GLSL 4.60 and return the expected pixels,
compute result 21500, and transform-feedback values 3,5,7,9. These checks do
not establish compatibility for every game, GPU generation, or macOS release.
Current upstream DXVK 3.1.1 was evaluated but not promoted: it requires
features absent from this driver combination. Weekly discovery reports
candidates; promotion requires a tested compatible set.

Sources, exact build instructions, notices, and archive hashes are recorded in
`scripts/graphics/README.md`, `sources.json`, and `artifacts.json`. Every DMG
includes the complete corresponding Wine/Mesa/Scotch sources in Sources.
