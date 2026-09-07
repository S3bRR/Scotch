# Scotch install locations

Every extra path Scotch creates is recorded in:

`~/Library/Application Support/com.s3brr.Scotch/InstallLedger.plist`

Uninstall (Settings → Uninstall Scotch, or `scotch uninstall --all`) reads that ledger plus the known roots below.

## App data (runtime)

| Path | What |
|---|---|
| `~/Library/Application Support/com.s3brr.Scotch/` | **Primary root.** Runtime, bottles, settings, logs, caches, ledger. |
| `…/Libraries/` | Wine, DXVK, DXMT, D3DMetal, Zink, Wine.app, GPU spoof dylib, winetricks |
| `…/Bottles/` | Default prefixes |
| `…/Logs/` | Launch logs |
| `…/WinetricksCache/` | Font/verb downloads |
| `…/LaunchEnv/` | Per-bottle env files for Wine.app |
| `…/ScotchSettings.plist` | App settings |
| `…/BottleVM.plist` | Bottle catalog |
| `…/InstallLedger.plist` | Recorded extra paths |

## Leftovers from older versions

| Path | What |
|---|---|
| `~/Library/Containers/com.s3brr.Scotch/` | Pre-1.1.0 settings, catalog, bottles |
| `~/Library/Logs/com.s3brr.Scotch/` | Pre-1.1.0 logs |
| `~/Library/Containers/com.s3brr.Scotch.Thumbnail/` | QuickLook sandbox (macOS may refuse deletion without Full Disk Access; uninstall then skips it) |
| `~/.cache/winetricks/` | Legacy winetricks cache |

## System / optional

| Path | What |
|---|---|
| `/usr/local/bin/scotch` | CLI symlink |
| `/Applications/Scotch.app` | App bundle (if installed there) |
| `~/Library/Preferences/com.s3brr.Scotch.plist` | UserDefaults |
| `~/Library/Caches/com.s3brr.Scotch/` | App cache |
| `~/Library/Saved Application State/com.s3brr.Scotch.savedState` | Window state |
| `/tmp/scotch_gpu_spoof.log` | GPU spoof debug log |
| `$TMPDIR/ScotchRuntimeDownloads` | First-run archives |
| `$TMPDIR/ScotchOverlays` | Overlay archives |
| `$TMPDIR/ScotchSteamInstall` | Steam installer temp |
| `$DARWIN_USER_CACHE_DIR/d3dm` | D3DMetal shader cache |
| `$DARWIN_USER_CACHE_DIR/dxmt` | DXMT shader cache |
| User-chosen `.app` shortcuts | Recorded in the ledger when created |
| Bottles outside the default folder | Recorded in the ledger and catalog |

## This workspace (development only)

These are **not** part of a user install. Remove them when finished working in this repo:

| Path | What |
|---|---|
| `/Users/s/Desktop/scotch_1/.build/` | SwiftPM build products |
| `/Users/s/Desktop/scotch_1/.release/` | Packaged `Scotch.app` + `Scotch.dmg` |

```bash
rm -rf /Users/s/Desktop/scotch_1/.build /Users/s/Desktop/scotch_1/.release
```

Nothing from this session was copied into `/Applications` or `~/Library`. First-run setup of the packaged app is what creates the Application Support tree.
