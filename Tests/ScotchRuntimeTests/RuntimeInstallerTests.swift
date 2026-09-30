import Foundation
import Testing
import ScotchDomain
import ScotchInfrastructure
@testable import ScotchRuntime

struct RuntimeInstallerTests {
    @Test func signingFailureRestoresPreviousRuntime() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        try FileManager.default.createDirectory(at: paths.librariesDirectory, withIntermediateDirectories: true)
        let marker = paths.librariesDirectory.appending(path: "previous-runtime")
        try "keep this runtime".write(to: marker, atomically: true, encoding: .utf8)

        let installer = RuntimeInstallerService(
            paths: paths, fileSystem: LocalFileSystem(), logger: TestLogger(),
            plistStore: PlistStore(), processRunner: ExtractionThenSigningFailure()
        )
        await #expect(throws: RuntimeInstallerError.self) {
            _ = try await installer.installAll(from: archives)
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "keep this runtime")
        #expect(!FileManager.default.fileExists(atPath: paths.wineBundleURL.path))
        let remaining = try FileManager.default.contentsOfDirectory(at: paths.applicationSupportDirectory, includingPropertiesForKeys: nil)
        #expect(!remaining.contains { $0.lastPathComponent.hasPrefix("Libraries.backup-") })
    }

    @Test func signingFailureDoesNotPublishFreshInstall() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let installer = RuntimeInstallerService(
            paths: paths, fileSystem: LocalFileSystem(), logger: TestLogger(),
            plistStore: PlistStore(), processRunner: ExtractionThenSigningFailure()
        )
        await #expect(throws: RuntimeInstallerError.self) {
            _ = try await installer.installAll(from: archives)
        }
        #expect(!FileManager.default.fileExists(atPath: paths.librariesDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: paths.runtimeManifestURL.path))
    }

    private var archives: DownloadedRuntimeArchives {
        let url = URL(fileURLWithPath: "/tmp/test-runtime.tar")
        let asset = ReleaseAsset(name: "test-runtime.tar", versionTag: "test", downloadURL: url, size: 0)
        return DownloadedRuntimeArchives(
            runtimeReleases: RuntimeReleases(wine: asset, dxvk: asset, dxmt: asset),
            wineArchive: url, dxvkArchive: url, dxmtArchive: url
        )
    }
}

private struct TestLogger: AppLogger {
    func info(_ message: String) {}
    func warning(_ message: String) {}
    func error(_ message: String) {}
}

private struct ExtractionThenSigningFailure: ProcessRunner {
    func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        fatalError("Tests use captureProcess")
    }

    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        if specification.executableURL.path == "/usr/bin/tar" {
            let destination = URL(fileURLWithPath: specification.arguments.last!)
            let wine = destination.appending(path: "wine/bin/wine")
            try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "test wine".write(to: wine, atomically: true, encoding: .utf8)
            return ""
        }
        throw ProcessRunnerError.nonZeroExit(displayName: specification.displayName, status: 1, output: "signing failed")
    }
}
