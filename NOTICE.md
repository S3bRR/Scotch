# Notices

Scotch is distributed under GPL-3.0. See [LICENSE](./LICENSE).

The native graphics support includes Mesa KosmicKrisp, MoltenVK, SPIRV-Tools,
and modified WineForge/Wine modules. Original license texts are retained under
ThirdParty/GraphicsSupport and installed with the runtime. Each release provides
complete corresponding Wine, Mesa, and Scotch source as the separate
`ScotchGraphicsSources.tar.xz` asset beside `Scotch.dmg`; see
[the build instructions](scripts/graphics/README.md) for versions, patches,
upstream origins, and rebuilding. Downloaded DXVK, DXMT, Wine, and GPTK payloads
retain their upstream notices. Sparkle's framework includes its own license.

The Wine child-window surface and D3DMetal hosting changes are adapted from
[typester/sake patches 0005 and 0006](https://github.com/typester/sake/tree/main/patches),
including James's implementation attached to Wine bug 60263. Those changes are
LGPL-2.1-or-later; attribution and their disclosed AI assistance are retained in
`scripts/graphics/wine-steam-surfaces.patch` and the corresponding source archive.
