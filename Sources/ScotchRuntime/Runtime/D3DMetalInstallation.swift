import Foundation
import ScotchDomain
import ScotchInfrastructure

/// Apple shims and the Wine loader are an ABI pair. Stock Wine 11.16
/// cannot load GPTK's PE modules (__wine_unix_call is no longer exported).
public enum D3DMetalInstallation {
    public static let version = "d3dmetal-3.0-scotch-r3"
    public static let toolkit = ReleaseAsset(
        name: "game-porting-toolkit-3.0-3.tar.xz", versionTag: "3.0-3",
        downloadURL: URL(string: "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz")!,
        size: 239_200_808, sha256: "d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e")
    public static let engine = MetalEngineInstallation.asset
    static let toolkitLibraryPath = "Game Porting Toolkit.app/Contents/Resources/wine/lib"
    static let modules = ["dxgi", "d3d11", "d3d12"]

    public static func isInstalled(at root: URL) -> Bool { (try? verify(at: root)) != nil }

    public static func verify(at root: URL) throws {
        let fm = FileManager.default
        let required = [
            "external/D3DMetal.framework/D3DMetal",
            "external/D3DMetal.framework/Resources/Info.plist",
            "external/libd3dshared.dylib"
        ] + modules.flatMap { ["wine/x86_64-windows/\($0).dll", "wine/x86_64-unix/\($0).so"] }
        for member in required {
            let file = root.appending(path: member)
            guard fm.fileExists(atPath: file.path),
                  file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw RuntimeInstallerError.installFailed("D3DMetal installation is incomplete: \(member)")
            }
        }
        try MetalEngineInstallation.verify(in: root.deletingLastPathComponent())
        for module in modules {
            try PackageArchitecture.verifyPE(at: root.appending(path: "wine/x86_64-windows/\(module).dll"), machine: 0x8664)
        }
    }
}
