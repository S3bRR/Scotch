import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct WinetricksEnsureInstalledTests {
    @Test func ensureInstalledFetchesScriptAndSetsExecutableMode() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.WinetricksEnsure.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "WinetricksEnsureTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        let mockNetwork = MockNetworkClient()
        let scriptBytes = Data("#!/bin/bash\necho ok\n".utf8)
        await mockNetwork.setDataHandler { _ in scriptBytes }

        let service = WinetricksService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            networkClient: mockNetwork
        )

        try await service.ensureInstalled()

        // File should exist with executable bit set, and contain the canned bytes.
        let written = try Data(contentsOf: paths.winetricksScriptURL)
        #expect(written == scriptBytes)
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.winetricksScriptURL.path(percentEncoded: false))
        let perms = attrs[.posixPermissions] as? NSNumber
        #expect(perms?.uint16Value == 0o755)

        // A second call short-circuits and does not re-fetch.
        let firstFetchCount = await mockNetwork.capturedRequests.count
        try await service.ensureInstalled()
        let secondFetchCount = await mockNetwork.capturedRequests.count
        #expect(firstFetchCount == 1)
        #expect(secondFetchCount == 1)
    }

    @Test func ensureInstalledSurfacesNonSuccessStatus() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.WinetricksEnsureFail.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "WinetricksEnsureFailTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        let mockNetwork = MockNetworkClient()
        await mockNetwork.setDataHandler { request in
            throw NetworkClientError.nonSuccessStatus(url: request.url, status: 503)
        }

        let service = WinetricksService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            networkClient: mockNetwork
        )

        do {
            try await service.ensureInstalled()
            Issue.record("expected downloadFailed")
        } catch let WinetricksError.downloadFailed(message) {
            #expect(message.contains("503"))
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
