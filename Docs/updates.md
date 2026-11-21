# Scotch updates: maintenance and release guide

The Update command in the main window and app menu runs one flow for both Scotch and approved runtime updates. It reports each part separately, installs compatible runtimes first, then authenticates/replaces/relaunches Scotch. Every accepted app update records a one-day continuation intent so the new build finishes checking runtimes and its bundled graphics profile after relaunch. A newer runtime requiring that app is then installed in the same Update flow. Games and bottle operations block installation; they are not killed by the updater.

Existing bottles retain their runtime selection. Newly created bottles use the latest installed default runtime. Bottle Runtime switches existing bottles in place without making a full copy. Older snapshots live beside the bottle under `.ScotchPrefixBackups`; the app leaves them in place and offers **Swap with Previous Snapshot** when one is available.

## Local build and verification

Use native SwiftPM, as in the 1.2.x releases:

```sh
SCOTCH_RELEASE_DIR="$PWD/.release/build18" SWIFT_BUILD_FLAGS='--build-system native' CODESIGN_IDENTITY=- bash scripts/package_release.sh
bash scripts/verify_release_bundle.sh .release/build18/Scotch.app
bash scripts/test_runtime_installation.sh
bash scripts/test_updates.sh
python3 scripts/test_app_updater.py --app .release/build18/Scotch.app
```

The last test uses two isolated updater-enabled app bundles, a loopback HTTP server, signed appcast/archive, unique test preferences, and a fixture save/catalog. It verifies real Sparkle replacement, relaunch, and subsequent detection that the updated build is current. It does not install a build into Applications or modify the real Scotch data directory. It requires the local signing tools and Keychain key described below, and an idle Wine environment. Automated feed checks in CI never require private keys.

Sparkle is pinned in Package.swift and Package.resolved and linked only by ScotchApp. The packaging script embeds and signs its framework and nested helpers before signing Scotch. Both app and QuickLook versions are 1.2.5, build 18 for this release. Minimum macOS remains 26.0. Existing ad-hoc signing is retained; Developer ID/notarization has not been added.

## Signing keys

Two separate private signing keys were generated in the local macOS Keychain. They are not in this repository, the DMG, or CI artifacts.

- Sparkle key: the default `ed25519` account used by Sparkle's generate_keys/sign_update tools. The public key is embedded as SUPublicEDKey in the app Info.plist. It is `9yIFm7v7AZzHk/XRbF/ruSLj4BVXKGCG6RmaiO0Tz7k=`.
- Runtime key: generic-password service `com.s3brr.Scotch.runtime-updates`, account `ed25519`. Its public key is embedded in UpdateConfiguration: `FFBpTlRRFiys/bDo7bALz3nVy8NHchA0IVOEn/DvQ+8=`.

Keep secure backups of these keys before public deployment. The current feed policy fails closed and does not expire failed feed-signature checks. Losing the app signing key without a supported Developer ID rotation path requires a manual bootstrap update. Do not commit private exports, pass private keys on command lines, or enable signing on untrusted PR jobs. Sparkle's update signature and Apple's app identity/notarization are separate mechanisms.

To install the matching tools on the release Mac, download Sparkle 2.10.1's official distribution and place its tools under `.build/updater-tools/bin`. generate_keys without arguments reuses an existing default key; do not substitute a different public key after shipping without a migration plan. `swift scripts/updates/RuntimeSigner.swift public-key` retrieves or creates the runtime key; verify the printed public key matches UpdateConfiguration before signing a public feed.

## App releases

1. Build the reviewed source and complete the local checks, including user game testing.
2. Create a local signed appcast and signed update archive:

   ```sh
   python3 scripts/updates/prepare_appcast.py --archive .release/build18/Scotch.dmg --tag v1.2.5 --output .release/build18/appcast --notes Docs/releases/1.2.5.md
   ```

   This uses the local Keychain, verifies the resulting feed, and never uploads anything. The production archive URL points to the versioned GitHub release asset.
3. After explicit release approval, publish the app release with Scotch.dmg, Scotch.dmg.sha256, ScotchGraphicsSources.tar.xz and ScotchGraphicsSources.tar.xz.sha256 using the existing repository convention. The corresponding source is a separate release download, not a folder inside the DMG. Do not announce the update feed first.
4. Copy the generated signed appcast.xml into updates/appcast.xml. Do not edit a signed XML document afterward; rerun generate_appcast/sign_update if changing it. Keep desired prior items when producing later feeds; generate_appcast can update an existing appcast in its archives directory.
5. Run the public-asset gate after upload:

   ```sh
   python3 scripts/updates/verify_public_assets.py --appcast updates/appcast.xml --runtime updates/runtime.json
   bash scripts/test_updates.sh --feed-only
   ```

6. Only then publish the signed feed through GitHub Pages. The manual update-feeds.yml workflow performs signature/public-byte verification before staging only appcast.xml and runtime.json under the `updates/` URL path.

Pages must be configured to deploy through GitHub Actions. The configured feed URLs are `https://s3brr.github.io/Scotch/updates/appcast.xml` and `/updates/runtime.json`. Publish them only after the corresponding release assets pass verification. The initial scaffold appcast and runtime feed are signed and empty, deliberately offering no nonexistent assets; release preparation replaces them with verified signed offers. Do not mark a local test build as a public update until the corresponding public bytes are available.

Users on versions without an updater need one manual app replacement to install the updater-enabled build. Replacing Scotch.app preserves Application Support and custom bottle folders. Uninstall is never part of the update process.

## Runtime publication

`updates/runtime-payload.json` is the human-editable input; `updates/runtime.json` is its signed envelope. Changes to the payload need a strictly newer revision and a new signature. Extend validUntil before expiry even if no version changes. Clients verify the envelope, reject expired/replayed/unsupported feeds and unsafe IDs/URLs, and download only exact supported layouts from immutable HTTPS GitHub release URLs.

Each approved set needs a unique immutable ID, title, minimumAppBuild, minimumMacOS (26 or later), architecture `arm64`, and packages for wine, dxvk, dxmt, and zink. Optional d3dmetal may be omitted. Each package specifies component, version, url, fileName, exact size, and SHA256. Set order defines promotion order, with the last compatible set selected for an update. A package URL/version is never synthesized from an unverified "latest" response.

Supported layouts are Gcenx Wine macOS archives with the stock WineMac driver (layout 1), DXVK Windows x64/x32 trees (layout 1), DXMT canonical builtin Windows/Unix trees (layout 2, minimumAppBuild 12), Mesa MSVC x64/x86 OpenGL/Gallium/EGL/GLES files (layout 1), and the complete GPTK 3.0-3 D3DMetal payload (layout 3, minimumAppBuild 12). The matched WineForge 0.6.0.3 engine and bundled native graphics support are separately pinned in the client and verified before activation. Windows DLL bitness and isolated engine startup are checked after extraction. Legacy D3DMetal repacks and native DXMT layouts are rejected because a DLL alone does not establish loader compatibility.

Bootstrap setup uses RuntimeAssets' fixed tested releases, rather than GitHub's moving latest/API responses. Signed feeds may select supported replacements. The native support profile remains client-coupled: changing Wine, its ABI, or the native support profile requires a matching client release and minimum build. A future native profile must receive a distinct immutable runtime-set ID and retain validation/launch support for previous profiles before public promotion. Never rewrite an old runtime ID with different native binaries. A signed feed may describe a future layout only when its minimumAppBuild excludes the current client; Update then obtains the app first and resumes.

After validating an approved combination, edit the payload and sign it:

```sh
swift scripts/updates/RuntimeSigner.swift sign updates/runtime-payload.json updates/runtime.json
bash scripts/test_updates.sh --feed-only
python3 scripts/updates/verify_public_assets.py --appcast updates/appcast.xml --runtime updates/runtime.json
```

Test against a signed local feed before promoting a new set. Never serve candidates immediately from upstream without layout, macOS/Wine, and appropriate game validation.

Runtime files are staged under RuntimeSets/staging-UUID. After verification and signing of Wine.app, the complete set is moved to RuntimeSets/ID. One atomic RuntimeSelection.plist write commits the new default. A crash before that point leaves the previous default active; an interrupted stage is ignored and cleaned up during a subsequent exclusive install. Archives are cached by content hash and revalidated on reuse, including archives initially fetched during bootstrap. A damaged selected set is offered for repair by Update, rebuilt from verified cache packages, and atomically exchanged into place after games have closed. Old runtime sets remain available for selected bottles and rollback; automatic pruning of runtime sets or legacy snapshots is deliberately not performed in this first implementation.

## Weekly discovery

runtime-candidates.yml runs weekly after it exists on the default branch and supports manual dispatch. It discovers relevant stable Wine, DXVK-macOS, DXMT, Mesa releases, downloads candidates to check exact size/digest, checks expected archive layout entries, tracks MoltenVK and the client-bundled native support profile separately, reports the pinned GPTK payload and compatible WineForge engine, and exercises the update-recovery probes. Its artifact is a candidate report, not an approved feed. Game compatibility remains explicitly unvalidated until tested. The workflow has read-only repository access and cannot publish updates.

## Preservation and recovery

Before app replacement, small metadata snapshots are stored under Application Support/UpdateBackups with a Locations.plist map. The last five metadata snapshots are retained. A corrupt catalog, corrupt program preferences, or future bottle schema cannot be overwritten with defaults by the new PlistStore safeguards. An offline external bottle stays referenced in the catalog.

A bottle runtime switch changes the runtime ID without copying or rolling back the prefix. Ordinary app/runtime downloads do not change registry or save files or invoke wineboot. Swapping with an older snapshot exchanges the two existing directories atomically without making another copy. The snapshot path then holds the previously active state.

Keep regular user backups as well. Manually downgrading to an older Scotch build that predates these schema safeguards is not a tested migration path; restore a compatible snapshot when necessary.

Build 12 includes full legacy graphics repair in the same Update flow. It uses the client-pinned archives and bundled support without depending on published feeds. MetalEngine, D3DMetal, DXMT, DXVK, Zink, the native support hashes, and the stock WineMac driver are checked. Libraries are cloned into an exclusive staging session, repaired and verified there, and atomically exchanged. The manifest changes only as part of that transaction. Failed repair preserves the previous files. Maximum uncached downloads are about 750 MB; verified cache hits avoid them. The repair state is recomputed after success.

First use of a different Wine engine also runs without a prefix backup. Close Wine processes before changing engines. The original prefix and its metadata remain untouched during download/repair. Native source rebuild instructions and source distribution are in scripts/graphics/README.md; each release provides complete corresponding Wine/Mesa/Scotch source as ScotchGraphicsSources.tar.xz beside the DMG, with a SHA256 file and an in-app source-availability notice.
