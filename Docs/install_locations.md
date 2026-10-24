# Scotch install locations

Every extra path Scotch creates is recorded in:

`~/Library/Application Support/com.s3brr.Scotch/InstallLedger.plist`

Uninstall (Settings → Uninstall Scotch, or `scotch uninstall --all`) reads that ledger plus the known roots below.

Uninstall also unregisters the QuickLook extension and both apps (Scotch.app, Wine.app) from LaunchServices, clears preferences through `defaults delete` (cfprefsd would otherwise write them back), and after Scotch exits retries anything macOS refused while it was running.

Not removed: **Rosetta 2**, which Scotch may install via `softwareupdate --install-rosetta`. It is a shared macOS component in SIP-protected `/Library/Apple`, used by every Intel app, and macOS provides no supported way to uninstall it.

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
| `~/Library/Containers/com.s3brr.Scotch.Thumbnail/` | QuickLook sandbox. Uninstall unregisters and stops the extension first; if macOS still refuses, it is retried after Scotch exits |
| `~/.cache/winetricks/` | Legacy winetricks cache |

## System / optional

| Path | What |
|---|---|
| `/usr/local/bin/scotch` | CLI symlink |
| `/Applications/Scotch.app` | App bundle (if installed there) |
| `~/Library/Preferences/com.s3brr.Scotch.plist` | UserDefaults |
| `~/Library/Caches/com.s3brr.Scotch/` | App cache |
| `~/Library/Caches/ScotchCmd/` | CLI URLSession cache |
| `~/Library/HTTPStorages/com.s3brr.Scotch/` | App HTTP storage |
| `~/Library/HTTPStorages/ScotchCmd/` | CLI HTTP storage |
| `~/Library/Application Scripts/com.s3brr.Scotch.Thumbnail/` | QuickLook scripts |
| `~/Library/Saved Application State/com.s3brr.Scotch.savedState` | Window state |
| `/tmp/scotch_gpu_spoof.log` | GPU spoof debug log |
| `$TMPDIR/ScotchRuntimeDownloads` | First-run archives |
| `$TMPDIR/ScotchOverlays` | Overlay archives |
| `$TMPDIR/ScotchSteamInstall` | Steam installer temp |
| `$DARWIN_USER_CACHE_DIR/d3dm` | D3DMetal shader cache |
| `$DARWIN_USER_CACHE_DIR/dxmt` | DXMT shader cache |
| `$DARWIN_USER_CACHE_DIR/<id>` and `$DARWIN_USER_TEMP_DIR/<id>` | Metal shader caches for `com.s3brr.Scotch`, `.WineBundle`, `.Thumbnail`, and `org.winehq.wine` (Wine processes outside Wine.app) |
| `~/Library/{Preferences,Caches,HTTPStorages,Saved Application State}/com.s3brr.Scotch.{WineBundle,Thumbnail}…` | Wine.app launcher and QuickLook extension state |
| `/tmp/.wine-<uid>/server-<dev>-<inode>` | Wine server socket directory per bottle (the parent is removed when empty) |
| `…/Steam/bin/cef/cef.win64/steamwebhelper_real.exe` | Inside bottles: Steam's real web helper, swapped for Scotch's launcher. Removed with the bottle |
| User-chosen `.app` shortcuts | Recorded in the ledger when created |
| Bottles outside the default folder | Recorded in the ledger and catalog |

## This workspace (development only)

These are **not** part of a user install. Remove them when finished working in this repo:

| Path | What |
|---|---|
| `<repo>/.build/` | SwiftPM build products |
| `<repo>/.release/` | Packaged `Scotch.app` + `Scotch.dmg` |

```bash
rm -rf <repo>/.build <repo>/.release
```

Nothing from this session was copied into `/Applications` or `~/Library`. First-run setup of the packaged app is what creates the Application Support tree.
