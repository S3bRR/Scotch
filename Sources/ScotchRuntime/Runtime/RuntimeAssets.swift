import Foundation
import ScotchDomain

/// The bootstrap is a tested matrix. Newer upstream releases enter the signed
/// approval feed after compatibility checks, rather than changing during setup.
public enum RuntimeAssets {
    public static let wine = ReleaseAsset(
        name: "wine-staging-11.16-osx64.tar.xz", versionTag: "11.16",
        downloadURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.16/wine-staging-11.16-osx64.tar.xz")!,
        size: 193_568_360, sha256: "cd68f230c773a761b8a0423a08c51fbe49e89b6e52246f3866898d259a4988c6")
    public static let dxvk = ReleaseAsset(
        name: "dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz", versionTag: "v1.10.3-20230507-repack",
        downloadURL: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz")!,
        size: 2_793_443, sha256: "acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477")
    public static let dxmt = MetalEngineInstallation.dxmt
    public static let zink = ReleaseAsset(
        name: "mesa3d-26.2.0-release-msvc.7z", versionTag: "26.2.0",
        downloadURL: URL(string: "https://github.com/pal1000/mesa-dist-win/releases/download/26.2.0/mesa3d-26.2.0-release-msvc.7z")!,
        size: 70_069_566, sha256: "dcb2719ef346dab5b609fcb193a5f13cfc4b0502e3f4de1ad43d349477402f47")
    static let stockMacDriverMember = "Wine Staging.app/Contents/Resources/wine/lib/wine/x86_64-unix/winemac.so"
    static let stockMacDriverSHA256 = "d37656b78dfbc9b2734acdd2c2e2f68051e423836bdfd484f4336103754793fa"
}
