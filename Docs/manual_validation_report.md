# Manual Validation Report

## Scope
Validation against discovered real bottle data under the active user profile.

## Summary
- PASS: 12
- FAIL: 0
- SKIP: 2

## Results

| Check | Result | Details |
|---|---|---|
| Rosetta availability | PASS | /Library/Apple/usr/libexec/oah/libRosettaRuntime |
| Runtime binaries | PASS | wine=True wineserver=True bundle=True |
| Runtime manifest | PASS | ~/Library/Application Support/com.s3brr.Scotch/Libraries/ScotchRuntimeManifest.plist |
| GPU spoof shim | PASS | ~/Library/Application Support/com.s3brr.Scotch/Libraries/VulkanSpoof/libscotch_gpu_spoof.dylib |
| Winetricks install | PASS | ~/Library/Application Support/com.s3brr.Scotch/Libraries/winetricks |
| Bottle discovery | PASS | source=~/Library/Containers/com.s3brr.Scotch/BottleCatalog.plist count=1 |
| Bottle metadata decode | PASS | ok=1 fail=0 |
| Program settings folder | PASS | ~/Library/Containers/com.s3brr.Scotch/Bottles/<bottle-uuid>/Program Settings |
| Log path writable | PASS | ~/Library/Logs/com.s3brr.Scotch |
| Steam flow readiness | SKIP | steam.exe not found in discovered bottles |
| Path handling with spaces | SKIP | No bottle path with spaces was found |
| EXE launch smoke test | PASS | rc=0 out=SCOTCH_V2_EXE_VALIDATION err= |
| MSI flow smoke test | PASS | rc=0 retry=False out= err=[mvk-info] MoltenVK version 1.4.1, supporting Vulkan version 1.4.334. 	The following 153 Vulkan extensions are supported |
| Process listing smoke test | PASS | rc=0 out="services.exe","56","Console","1","0 K" "winedevice.exe","68","Console","1","0 K" "plugplay.exe","104","Console","1","0  err= |

## Paths
- Container: `~/Library/Containers/com.s3brr.Scotch`
- App Support: `~/Library/Application Support/com.s3brr.Scotch`
- Logs: `~/Library/Logs/com.s3brr.Scotch`
