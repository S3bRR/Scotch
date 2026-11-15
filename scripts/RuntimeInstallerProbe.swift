import Foundation
import Darwin
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

@main
struct RuntimeInstallerProbe {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("Installer regression failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
    }

    private static func run() async throws {
        let mesaArchive = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchInstallerProbe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = try await Fixtures(root: root)
        let toolkit = URL(fileURLWithPath: CommandLine.arguments[2])
        let engine = URL(fileURLWithPath: CommandLine.arguments[3])

        for scenario in Scenario.allCases {
            let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.InstallerProbe.\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory); try? FileManager.default.removeItem(at: paths.cachesDirectory) }
            let network = FixtureNetwork(mesaArchive: mesaArchive, d3dmetalArchive: toolkit, engineImage: engine, scenario: scenario)
            let installer = makeInstaller(paths: paths, network: network)
            let previousMarker = paths.librariesDirectory.appending(path: "previous-install")
            if scenario == .badChecksum || scenario == .missingZinkDLL {
                try write("previous runtime", to: previousMarker)
            }

            do {
                let (manifest, overlays) = try await installer.installAll(from: fixtures.archives)
                try require(scenario != .badChecksum && scenario != .missingZinkDLL, "Required Zink failure must abort setup")
                let d3dmetal = overlays.first { $0.component == .d3dmetal }
                try require(d3dmetal != nil, "D3DMetal result must be reported")
                if scenario == .d3dmetalAvailable || scenario == .reinstall {
                    try require(d3dmetal?.succeeded == true && manifest.d3dmetalVersion != nil, "Available D3DMetal must install: \(d3dmetal?.errorMessage ?? "unknown")")
                } else {
                    try require(d3dmetal?.errorMessage != nil && manifest.d3dmetalVersion == nil, "D3DMetal failure must return a warning")
                    try require(!FileManager.default.fileExists(atPath: paths.librariesDirectory.appending(path: "D3DMetal").path), "Partial D3DMetal must be removed")
                }
                for architecture in ["x64", "x32"] {
                    for name in ["opengl32.dll", "libgallium_wgl.dll"] {
                        let url = paths.librariesDirectory.appending(path: "Zink/\(architecture)/\(name)")
                        let handle = try FileHandle(forReadingFrom: url)
                        let magic = try handle.read(upToCount: 2)
                        try handle.close()
                        try require(magic == Data([0x4d, 0x5a]), "Zink must contain the actual Windows DLLs")
                    }
                    try require(!FileManager.default.fileExists(atPath: paths.librariesDirectory.appending(path: "Zink/\(architecture)/d3d10warp.dll").path), "Unrelated Mesa drivers must not be injected")
                }
                try require(await installer.isRuntimeInstalled(), "Runtime must be ready after installation")
                let restarted = makeInstaller(paths: paths, network: network)
                try require(await restarted.currentManifest() == manifest, "Restart must accept the installed manifest")

                if scenario == .reinstall {
                    for asset in [D3DMetalInstallation.toolkit, D3DMetalInstallation.engine] {
                        try? FileManager.default.removeItem(at: paths.cachesDirectory.appending(path: "RuntimePackages/" + asset.sha256!))
                    }
                    await network.makeD3DMetalUnavailable()
                    let (reinstalled, results) = try await restarted.installAll(from: fixtures.archives)
                    try require(reinstalled.d3dmetalVersion == manifest.d3dmetalVersion, "Reinstall must retain working D3DMetal")
                    try require(results.first { $0.component == .d3dmetal }?.errorMessage != nil, "Reinstall must report the download failure")
                    try require(await restarted.isRuntimeInstalled(), "Retained D3DMetal must still verify")
                }

                if scenario == .d3dmetalMissing {
                    let drifts = await restarted.overlayDrifts()
                    try require(!drifts.contains { $0.component == .d3dmetal }, "Missing optional backend must not advertise an update")
                    try FileManager.default.removeItem(at: paths.librariesDirectory.appending(path: "Zink/x64/libgallium_wgl.dll"))
                    try require(!(await restarted.isRuntimeInstalled()), "Missing Gallium dependency must invalidate readiness")
                    try require(await restarted.currentManifest() == nil, "Incomplete Zink must not expose a ready manifest")
                }
                if scenario == .d3dmetalAvailable {
                    try FileManager.default.removeItem(at: paths.librariesDirectory.appending(path: "D3DMetal/wine/x86_64-windows/d3d12.dll"))
                    try require(await restarted.isRuntimeInstalled(), "Damaged optional D3DMetal must not block Zink")
                    let current = await restarted.currentManifest()
                    try require(current != nil && current?.d3dmetalVersion == nil, "Damaged optional D3DMetal must not be advertised as installed")
                }
            } catch {
                guard scenario == .badChecksum || scenario == .missingZinkDLL,
                      error is RuntimeInstallerError else { throw error }
                let text = error.localizedDescription
                try require(text.contains(scenario == .badChecksum ? "Checksum mismatch" : "x86/libgallium_wgl.dll"), "Expected required Zink failure, got \(text)")
                try require(try String(contentsOf: previousMarker, encoding: .utf8) == "previous runtime", "Required-component failure must restore the previous runtime")
                try require(!FileManager.default.fileExists(atPath: paths.runtimeManifestURL.path), "A failed install must not publish a manifest")
            }
            let remaining = try FileManager.default.contentsOfDirectory(at: paths.applicationSupportDirectory, includingPropertiesForKeys: nil)
            try require(!remaining.contains { $0.lastPathComponent.hasPrefix("Libraries.backup-") }, "No backup may be left behind")
            print("Passed: \(scenario.rawValue)")
        }
    }

    private static func makeInstaller(paths: AppPaths, network: FixtureNetwork) -> RuntimeInstallerService {
        RuntimeInstallerService(
            paths: paths, fileSystem: LocalFileSystem(), logger: ProbeLogger(),
            plistStore: PlistStore(), processRunner: ProbeRunner(scenario: network.scenario), networkClient: network
        )
    }
}

private enum Scenario: String, CaseIterable, Sendable {
    case d3dmetalMissing = "D3DMetal 404 does not block Zink or restart"
    case d3dmetalAvailable = "available D3DMetal installs and verifies"
    case partialD3DMetal = "incomplete D3DMetal is removed without blocking Zink"
    case reinstall = "reinstall retains working D3DMetal on 404"
    case badChecksum = "Zink checksum failure rolls back"
    case missingZinkDLL = "missing Zink dependency rolls back"
}

private struct Fixtures {
    let archives: DownloadedRuntimeArchives
    init(root: URL) async throws {
        func archive(_ name: String, files: [String]) async throws -> URL {
            let source = root.appending(path: name)
            for file in files {
                let url = source.appending(path: file)
                try write("fixture", to: url)
                if file.hasSuffix(".dll") {
                    var pe = Data(repeating: 0, count: 256); pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 128; pe[128] = 0x50; pe[129] = 0x45
                    let x64 = file.hasPrefix("x86_64-windows/") || file.hasPrefix("x64/")
                    pe[132] = x64 ? 0x64 : 0x4c; pe[133] = x64 ? 0x86 : 0x01
                    try pe.write(to: url)
                }
            }
            let destination = root.appending(path: "\(name).tar.gz")
            _ = try await DefaultProcessRunner().captureProcess(ProcessSpecification(
                executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-czf", destination.path, "-C", source.path, "."], displayName: "Create fixture"
            ), outputFileHandle: nil)
            return destination
        }
        let wine = try await archive("wine", files: ["wine/bin/wine", "wine/bin/wineserver", "wine/lib/wine/x86_64-unix/winemac.so", "wine/share/wine/mono/wine-mono-11.3.0/lib/mono/4.5/mscorlib.dll", "wine/share/wine/gecko/wine-gecko-2.47.4-x86_64/xul.dll", "wine/share/wine/gecko/wine-gecko-2.47.4-x86/xul.dll"])
        let dxvk = try await archive("dxvk", files: ["x64/d3d11.dll", "x32/d3d11.dll"])
        let dxmt = try await archive("dxmt", files: ["x86_64-windows/d3d11.dll", "i386-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "i386-windows/dxgi.dll", "x86_64-windows/winemetal.dll", "i386-windows/winemetal.dll", "x86_64-unix/winemetal.so"])
        func asset(_ name: String, version: String, archive: URL) -> ReleaseAsset {
            ReleaseAsset(name: name, versionTag: version, downloadURL: archive, size: 0)
        }
        archives = DownloadedRuntimeArchives(
            runtimeReleases: RuntimeReleases(
                wine: asset("wine", version: "11.16", archive: wine),
                dxvk: asset("dxvk", version: "v1.10.3-20230507-repack", archive: dxvk),
                dxmt: asset("dxmt", version: "v0.80", archive: dxmt)
            ), wineArchive: wine, dxvkArchive: dxvk, dxmtArchive: dxmt
        )
    }
}

private actor FixtureNetwork: NetworkClient {
    let mesaArchive: URL
    let d3dmetalArchive: URL
    let engineImage: URL
    nonisolated let scenario: Scenario
    private var forceD3DMetal404 = false

    init(mesaArchive: URL, d3dmetalArchive: URL, engineImage: URL, scenario: Scenario) {
        self.mesaArchive = mesaArchive
        self.d3dmetalArchive = d3dmetalArchive
        self.engineImage = engineImage
        self.scenario = scenario
    }

    func makeD3DMetalUnavailable() { forceD3DMetal404 = true }

    func data(for request: NetworkRequest) async throws -> Data {
        throw ProbeError(message: "Unexpected data request: \(request.url)")
    }

    func download(from request: NetworkRequest) async throws -> URL {
        let source: URL
        if request.url.absoluteString == "https://github.com/pal1000/mesa-dist-win/releases/download/26.2.0/mesa3d-26.2.0-release-msvc.7z" {
            source = mesaArchive
        } else if request.url == D3DMetalInstallation.toolkit.downloadURL {
            if forceD3DMetal404 || (scenario != .d3dmetalAvailable && scenario != .reinstall && scenario != .partialD3DMetal) {
                throw NetworkClientError.nonSuccessStatus(url: request.url, status: 404)
            }
            source = d3dmetalArchive
        } else if request.url == D3DMetalInstallation.engine.downloadURL {
            source = engineImage
        } else {
            throw ProbeError(message: "Unexpected download: \(request.url)")
        }
        let temporary = FileManager.default.temporaryDirectory.appending(path: "ScotchProbeDownload-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: temporary)
        if scenario == .badChecksum && source == mesaArchive {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: Data([0]))
            try handle.close()
        }
        return temporary
    }
}

private struct ProbeRunner: ProcessRunner {
    let scenario: Scenario

    func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        try DefaultProcessRunner().streamProcess(specification, outputFileHandle: outputFileHandle)
    }

    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        let result = try await DefaultProcessRunner().captureProcess(specification, outputFileHandle: outputFileHandle)
        if specification.executableURL.path == "/usr/bin/tar", specification.arguments.first == "-xf", let index = specification.arguments.firstIndex(of: "-C"), index + 1 < specification.arguments.count {
            let destination = specification.arguments[index + 1]
            if scenario == .partialD3DMetal && specification.arguments.contains(where: { $0.hasSuffix(D3DMetalInstallation.toolkit.name) }) {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: destination).appending(path: "Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework"))
            }
            if scenario == .missingZinkDLL && specification.arguments.contains(where: { $0.hasSuffix(".7z") }) {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: destination).appending(path: "x86/libgallium_wgl.dll"))
            }
        }
        return result
    }
}

private struct ProbeLogger: AppLogger {
    func info(_ message: String) {}
    func warning(_ message: String) {}
    func error(_ message: String) {}
}

private struct ProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeError(message: message) }
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}
