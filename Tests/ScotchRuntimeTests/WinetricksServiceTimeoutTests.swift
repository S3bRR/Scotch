import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct WinetricksServiceTimeoutTests {
    @Test func installCoreFontsForwardsPerVerbTimeoutToProcessRunner() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.WinetricksTimeout.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "WinetricksTimeoutTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }
        try fileSystem.createDirectory(at: paths.librariesDirectory)

        // Pre-stage a stub winetricks script so ensureInstalled() short-circuits.
        let scriptURL = paths.winetricksScriptURL
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path(percentEncoded: false))

        let recorder = SpecCapturingProcessRunner()
        let service = WinetricksService(paths: paths, fileSystem: fileSystem, logger: logger, processRunner: recorder)

        let bottle = BottleSummary(
            id: BottleID(rawValue: "wt-bottle"),
            directoryURL: paths.containerDirectory.appending(path: "wt-bottle"),
            settings: BottleSettings(),
            isAvailable: true
        )

        try await service.installCoreFonts(in: bottle, progress: nil)

        let captured = await recorder.capturedSpecifications
        #expect(captured.count == WinetricksService.coreFontVerbs.count)
        for spec in captured {
            #expect(spec.timeout == 120)
            #expect(spec.executableURL.path.hasSuffix("/bin/bash"))
        }
    }

    @Test func runHeadlessPropagatesTimeoutErrorAsWinetricksError() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.WinetricksTimeout.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "WinetricksTimeoutTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }
        try fileSystem.createDirectory(at: paths.librariesDirectory)
        let scriptURL = paths.winetricksScriptURL
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path(percentEncoded: false))

        let throwing = ThrowingProcessRunner(
            error: ProcessRunnerError.timeout(displayName: "winetricks fakeverb", elapsed: 12)
        )
        let service = WinetricksService(paths: paths, fileSystem: fileSystem, logger: logger, processRunner: throwing)

        do {
            _ = try await service.installCoreFonts(in: BottleSummary(
                id: BottleID(rawValue: "wt-bottle"),
                directoryURL: paths.containerDirectory.appending(path: "wt-bottle"),
                settings: BottleSettings(),
                isAvailable: true
            ), progress: nil)
            Issue.record("expected WinetricksError")
        } catch let WinetricksError.executionFailed(message) {
            #expect(message.contains("Timed out"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}

private actor SpecCapturingProcessRunner: ProcessRunner {
    private(set) var capturedSpecifications: [ProcessSpecification] = []

    nonisolated func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        Task { await record(specification) }
        return AsyncStream { continuation in
            continuation.yield(.started)
            continuation.yield(.terminated(0))
            continuation.finish()
        }
    }

    nonisolated func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        await record(specification)
        return ""
    }

    private func record(_ specification: ProcessSpecification) {
        capturedSpecifications.append(specification)
    }
}

private final class ThrowingProcessRunner: ProcessRunner, @unchecked Sendable {
    let error: Error
    init(error: Error) { self.error = error }

    func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        throw error
    }

    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        throw error
    }
}
