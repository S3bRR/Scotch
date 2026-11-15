# Scotch native graphics support

The release asset `ScotchGraphicsSources.tar.xz`, available beside `Scotch.dmg`,
contains the complete pinned
WineForge and Mesa source archives, this Scotch worktree, the patches, licenses,
and build scripts. Extract it with `tar -xf ScotchGraphicsSources.tar.xz` and
work from its `Scotch` directory. The source archive is separate from the app;
users do not need to build or install it to use Scotch.

## What is built

`sources.json` pins every upstream archive and the compiler-tool versions.
`artifacts.json` records the packaged file hashes. `package_support.py` produces
`Sources/ScotchRuntime/Resources/GraphicsSupport.tar.xz` and regenerates the
client's verification table. The archive contains:

- A small Vulkan router selecting MoltenVK 1.4.2 for Wine/DXVK instances and
  KosmicKrisp for Mesa Zink instances. It keeps dispatch per instance/device and
  exports the Metal surface entry point WineMac probes directly.
- Mesa KosmicKrisp built for x86_64 under Rosetta, targeting macOS 26.0. The
  transform-feedback and RGB32 texel-buffer changes are confined to
  `src/kosmickrisp`; origins are recorded in `sources.json`. No other Mesa
  driver or protected source directory is modified.
- WineForge 0.6.0.3's Vulkan-enabled `win32u`, `winemac`, `ntdll`, and `winevulkan` Unix
  modules. The WoW64 properties patch uses a heap conversion arena for the two
  32-bit physical-device-properties calls; the generator carries the same fix.
- Native profile 2 adds cross-process child-window hosting and the D3DMetal
  window-record adaptation from the attributed Steam surface patch. A scoped
  loader policy selects DXMT only for Steam's CEF executable; games keep their
  configured renderer. The client registers the additional winemetal PE builtin
  in fresh prefixes. Original Steam files are not replaced.
- Original notices and source references. Runtime dylibs use portable loader
  paths, have no Homebrew dependencies, target macOS 26, and are ad-hoc signed.

## Rebuilding on Apple Silicon

Use Xcode command-line tools and the versions in `sources.json`: LLVM/Clang
build tools, SPIRV-LLVM-Translator, libclc, Meson, Ninja, Bison 3, Python with
Mako/PyYAML/packaging, pkg-config, xz, and 7-Zip. FreeType headers must match the
WineForge runtime; do not link the rebuilt x86_64 Wine modules to arm64 Homebrew
libraries. The build script uses Apple's compiler for the actual native modules.
Build dependencies may live in a private directory; `--env-json` accepts a JSON
object containing PATH/PKG_CONFIG_PATH/CMAKE_PREFIX_PATH for that toolchain.

Download the exact archives listed in `sources.json`, plus the WineForge DMG
pinned by `MetalEngineInstallation.swift`. Mount the DMG read-only at a unique
local path. Do not run its installer. The engine argument below points inside
`WineForge.app/Contents/Resources/Engine/WineForgeCore` on that mount.

Extract the SDK without running its system installer:

```sh
python3 scripts/graphics/extract_sdk.py /path/to/vulkansdk-macos-1.4.363.1.zip .build/sdk
```

Then run, substituting local archive/tool locations:

```sh
python3 scripts/graphics/build_support.py \
  --mesa-archive /path/to/mesa-cbc51df.tar.gz \
  --wine-archive /path/to/WineForge-0.6.0.3.tar.gz \
  --moltenvk-archive /path/to/MoltenVK-macos-privateapi.tar \
  --sdk .build/sdk/macOS \
  --engine /path/to/mount/WineForge.app/Contents/Resources/Engine/WineForgeCore \
  --freetype-include /path/to/freetype/include/freetype2 \
  --bison /path/to/bison \
  --work .build/graphics-rebuild --jobs 8
```

`--work` must be new. Use `--no-package` to validate a clean rebuild while
preserving existing shipped resources. Source digests are checked before
extraction; the build applies the checked-in patches, builds native compiler
helpers, cross-builds KosmicKrisp, and builds the four Wine modules. Packaging
checks dependencies, architectures, deployment targets, and signatures. Detach
only the mount created for this build afterward.

## Verification and release

`bash scripts/test_live_runtime.sh /path/to/verified-runtime-archives` exercises
the shipping installer under a unique test application ID, then real GPU
readback/presentation for DXVK, DXMT, D3DMetal, and Zink. It tests both Windows
architectures where supported, OpenGL 4.5 compute/DSA/RGB32 buffers, transform
feedback, combined Direct3D plus Zink, repair, and prefix recovery. The optional
archive directory saves downloads but every cached archive is rehashed. Tests
require Rosetta and mingw-w64 cross compilers. They never open a real Scotch
bottle. Specific games and other GPU/macOS combinations still require testing.

`DriverIdentitySmoke.c` separately checks simultaneous native driver instances,
AMD/NVIDIA preset driver versions, and Zink's unchanged Apple identity. With the
support archive extracted into a private test directory, compile it for x86_64
using the pinned Mesa source's `include` directory and pass the extracted
`Graphics/libvulkan.1.dylib` as its only argument. It does not open a Wine prefix.

`package_sources.py` prepares this corresponding-source archive from verified
original archives plus the current Scotch files. `package_release.sh` outputs
it and its checksum beside the DMG for upload to the same release. The mounted
DMG contains only Scotch.app and the Applications shortcut. App/runtime update publication is a separate,
explicit release step described in `Docs/updates.md`.
