import Foundation
import ScotchDomain
import ScotchInfrastructure

/// DXMT's builtin modules and Apple's D3DMetal shims require this loader ABI.
/// Keep it separate from Apple's payload so DXMT never depends on that download.
public enum MetalEngineInstallation {
    public static let version = "wineforge-0.6.0.3-scotch-1"
    public static let asset = ReleaseAsset(
        name: "WineForge.dmg", versionTag: "0.6.0.3",
        downloadURL: URL(string: "https://github.com/Alien4042x/WineForge/releases/download/0.6.0.3/WineForge.dmg")!,
        size: 226_235_940, sha256: "ada28bd6b4be81aac69669a3af0e383380e116b130469c55066dfb5e9956ecbf")

    public static let dxmt = ReleaseAsset(
        name: "dxmt-v0.80-builtin.tar.gz", versionTag: "v0.80",
        downloadURL: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!,
        size: 18_681_669, sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d")

    public static func verify(in libraries: URL) throws {
        let root = libraries.appending(path: "MetalEngine")
        let required = ["Engine/bin/wine", "Engine/bin/wineserver",
            "Engine/lib/wine/x86_64-unix/ntdll.so", "Engine/lib/wine/x86_64-unix/winemac.so",
            "Engine/lib/wine/x86_64-windows/ntdll.dll", "Wine.app/Contents/MacOS/wine-launcher",
            "Engine/share/wine/mono/wine-mono-11.3.0/lib/mono/4.5/mscorlib.dll",
            "Engine/share/wine/gecko/wine-gecko-2.47.4-x86_64/xul.dll",
            "Engine/share/wine/gecko/wine-gecko-2.47.4-x86/xul.dll"]
        for member in required {
            let file = root.appending(path: member)
            guard FileManager.default.fileExists(atPath: file.path),
                  file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw RuntimeInstallerError.installFailed("The Metal Wine engine needs repair: \(member). Use Update.")
            }
        }
        guard (try? String(contentsOf: root.appending(path: "EngineVersion"), encoding: .utf8)) == version else {
            throw RuntimeInstallerError.installFailed("The Metal Wine engine needs repair. Use Update.")
        }
    }

    public static func verifyDXMT(in libraries: URL) throws {
        let root = libraries.appending(path: "DXMT")
        for (architecture, machine) in [("x86_64-windows", UInt16(0x8664)), ("i386-windows", UInt16(0x014c))] {
            for module in ["dxgi", "d3d11", "winemetal"] {
                try PackageArchitecture.verifyPE(at: root.appending(path: "\(architecture)/\(module).dll"), machine: machine)
            }
        }
        guard FileManager.default.fileExists(atPath: root.appending(path: "x86_64-unix/winemetal.so").path) else {
            throw RuntimeInstallerError.installFailed("DXMT's builtin bridge needs repair. Use Update.")
        }
    }
}
