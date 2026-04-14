import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct TarArchiveTests {
    @Test func extractsRealTarball() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: "scotch_tar_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        // Build a fixture: workspace/source/{a.txt, sub/b.txt}
        let source = workspace.appending(path: "source")
        try FileManager.default.createDirectory(at: source.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: source.appending(path: "a.txt"))
        try Data("beta".utf8).write(to: source.appending(path: "sub/b.txt"))

        // tar it via the system tar so the test only depends on /usr/bin/tar.
        let archive = workspace.appending(path: "fixture.tar")
        let pack = Process()
        pack.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        pack.arguments = ["-cf", archive.path(percentEncoded: false), "-C", workspace.path(percentEncoded: false), "source"]
        try pack.run()
        pack.waitUntilExit()
        #expect(pack.terminationStatus == 0)

        // Extract via our async API.
        let dest = workspace.appending(path: "extracted")
        try await TarArchive.extract(archive, to: dest, using: DefaultProcessRunner())

        let extractedAlpha = try Data(contentsOf: dest.appending(path: "source/a.txt"))
        let extractedBeta = try Data(contentsOf: dest.appending(path: "source/sub/b.txt"))
        #expect(String(data: extractedAlpha, encoding: .utf8) == "alpha")
        #expect(String(data: extractedBeta, encoding: .utf8) == "beta")
    }

    @Test func extractFailsCleanlyForBadArchive() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: "scotch_tar_bad_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let bogus = workspace.appending(path: "not-a-tar.bin")
        try Data("not a real tar archive".utf8).write(to: bogus)

        let dest = workspace.appending(path: "extracted")
        do {
            try await TarArchive.extract(bogus, to: dest, using: DefaultProcessRunner())
            Issue.record("expected extractionFailed")
        } catch let RuntimeInstallerError.extractionFailed(message) {
            #expect(message.contains("tar"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
