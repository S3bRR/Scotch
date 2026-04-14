import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct RuntimeInstallerServiceStrictnessTests {
    @Test func runtimeIsNotInstalledWhenRequiredOverlayVersionsMissingFromManifest() async throws {
        let harness = try StrictRuntimeHarness()
        defer { harness.cleanup() }

        try harness.createCoreArtifacts(includeOverlays: true)
        let incompleteManifest = RuntimeManifest(
            wineVersion: "wine-11.6",
            dxvkVersion: "v1.10.3",
            dxmtVersion: "v0.74",
            d3dmetalVersion: nil,
            winemacPatchVersion: nil,
            zinkVersion: nil
        )
        try await harness.plistStore.write(incompleteManifest, to: harness.paths.runtimeManifestURL)

        #expect(await harness.installer.isRuntimeInstalled() == false)
        #expect(await harness.installer.currentManifest() == nil)
    }

    @Test func runtimeIsNotInstalledWhenAnyRequiredOverlayArtifactIsMissing() async throws {
        let harness = try StrictRuntimeHarness()
        defer { harness.cleanup() }

        try harness.createCoreArtifacts(includeOverlays: false)
        let completeManifest = RuntimeManifest(
            wineVersion: "wine-11.6",
            dxvkVersion: "v1.10.3",
            dxmtVersion: "v0.74",
            d3dmetalVersion: "d3dmetal-3.0",
            winemacPatchVersion: "wine-openglpatch-11.6",
            zinkVersion: "zink-1.0"
        )
        try await harness.plistStore.write(completeManifest, to: harness.paths.runtimeManifestURL)

        #expect(await harness.installer.isRuntimeInstalled() == false)
        #expect(await harness.installer.currentManifest() == nil)
    }

    @Test func runtimeIsInstalledOnlyWhenManifestAndArtifactsAreComplete() async throws {
        let harness = try StrictRuntimeHarness()
        defer { harness.cleanup() }

        try harness.createCoreArtifacts(includeOverlays: true)
        let completeManifest = RuntimeManifest(
            wineVersion: "wine-11.6",
            dxvkVersion: "v1.10.3",
            dxmtVersion: "v0.74",
            d3dmetalVersion: "d3dmetal-3.0",
            winemacPatchVersion: "wine-openglpatch-11.6",
            zinkVersion: "zink-1.0"
        )
        try await harness.plistStore.write(completeManifest, to: harness.paths.runtimeManifestURL)

        #expect(await harness.installer.isRuntimeInstalled() == true)
        #expect(await harness.installer.currentManifest() == completeManifest)
    }
}

private struct StrictRuntimeHarness {
    let paths: AppPaths
    let fileSystem: LocalFileSystem
    let plistStore: PlistStore
    let installer: RuntimeInstallerService

    init() throws {
        let bundleIdentifier = "com.s3brr.Scotch.StrictRuntime.\(UUID().uuidString)"
        self.paths = AppPaths(bundleIdentifier: bundleIdentifier)
        self.fileSystem = LocalFileSystem()
        self.plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RuntimeInstallerServiceStrictnessTests")
        self.installer = RuntimeInstallerService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            plistStore: plistStore,
            processRunner: DefaultProcessRunner()
        )

        try? fileSystem.removeItem(at: paths.containerDirectory)
        try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
        try fileSystem.createDirectory(at: paths.containerDirectory)
        try fileSystem.createDirectory(at: paths.applicationSupportDirectory)
    }

    func cleanup() {
        try? fileSystem.removeItem(at: paths.containerDirectory)
        try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
    }

    func createCoreArtifacts(includeOverlays: Bool) throws {
        try touch(paths.wineBinaryURL)
        try touch(paths.wineServerBinaryURL)
        try fileSystem.createDirectory(at: paths.wineBundleURL)
        try fileSystem.createDirectory(at: paths.librariesDirectory.appending(path: "DXVK"))
        try fileSystem.createDirectory(at: paths.librariesDirectory.appending(path: "DXMT"))
        try touch(paths.librariesDirectory.appending(path: "VulkanSpoof/libscotch_gpu_spoof.dylib"))

        if includeOverlays {
            try touch(paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so"))
            try touch(paths.librariesDirectory.appending(path: "D3DMetal/x64/d3d12.dll"))
            try touch(paths.librariesDirectory.appending(path: "D3DMetal/D3DMetal.framework/Versions/A/D3DMetal"))
            try touch(paths.librariesDirectory.appending(path: "Zink/x64/opengl32.dll"))
        }
    }

    private func touch(_ url: URL) throws {
        try fileSystem.createDirectory(at: url.deletingLastPathComponent())
        if !fileSystem.fileExists(at: url) {
            try Data().write(to: url)
        }
    }
}
