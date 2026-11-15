# Steam installation and rendering repair — build 14

Build 13's sign-in-state checks did not prove that Steam's window painted. The
user still saw a black window. Steam's software compositor also draws across
process boundaries, so disabling GPU rendering did not resolve the window
ownership problem. During investigation its bootstrap log additionally showed
`Verifying all executable checksums` and a bad CRC after replacing the helper.
The helper-replacement approach was rejected for this build.

Build 14 uses the matched WineForge/Wine 11.16 engine for every graphics backend.
Its WineMac driver includes cross-process child-window layer hosting and the
D3DMetal window-record adaptation from the attributed patches recorded in
`scripts/graphics/wine-steam-surfaces.patch`. The source pins, LGPL notices,
complete corresponding sources and build recipe ship with the DMG.

A narrowly scoped Wine loader policy routes only the executable ending in
`bin/cef/cef.win64/steamwebhelper.exe` through the installed builtin DXMT runtime.
Its game processes keep the bottle's configured graphics backend. Steam's own
CEF Windows sandbox compatibility switch remains necessary for this engine's
renderer startup; GPU rendering and compositing stay enabled. No macOS security,
TLS settings, Steam executable checksums or vendor DLLs are patched. The old
Scotch helper is restored from its saved original when detected; recovery copies
are retained. New vendor helpers are not overwritten with older backups.

All bottles now use one matched engine, avoiding mixed loader/driver ABIs across
Steam and its games. Before adopting an existing prefix, Scotch takes a full
recovery snapshot. Existing game files and saves stay in place. Use Update to
repair an existing native runtime installation after replacing the app; close
Wine processes before activation. New runtime installations include the repair.

The Install Steam action still waits for the official silent NSIS installer to
exit, verifies and pins Steam, then launches it through Wine.app. Client updates
may continue before sign-in appears. Installation status stays visible while
setup runs, and the main backend/runtime controls wait until it finishes.

`bash scripts/test_steam.sh` checks argument boundaries and legacy helper
recovery. The live `--resume` check tests all four backends in a retained isolated
bottle. `--install-only /path/to/Libraries` makes a new isolated bottle and invokes
the actual Install Steam action and first bootstrap. Live checks require a fresh
sign-in state, enabled GPU compositing, no injected software/single-process flags,
and no CEF GPU or WineDbg crash loop. They do not sign into an account.

On the development M5 Pro/macOS 27.2.1 machine, the user also confirmed Steam's
visible window works with the new native runtime. Other games, Mac models and
macOS releases still need their own coverage. Native desktop automation could
not reliably bind Wine's accessibility surface; sign-in logs alone are never
reported as visual verification.
