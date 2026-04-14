import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct WinetricksServiceTests {
    @Test func parsesListAllOutputIntoCategoriesAndVerbs() async throws {
        let service = makeService()
        let output = """
        ===== apps =====
        app1 App one description
        app2 App two description
        ===== fonts =====
        corefonts Microsoft core fonts
        """

        let parsed = await service.parseListAllOutput(output)
        #expect(parsed.count == 2)
        #expect(parsed[0].category == .apps)
        #expect(parsed[0].verbs.map(\.name) == ["app1", "app2"])
        #expect(parsed[1].category == .fonts)
        #expect(parsed[1].verbs.first?.name == "corefonts")
    }

    @Test func baseEnvironmentIncludesWinePrefixAndPath() async throws {
        let service = makeService()
        let bottle = BottleSummary(
            id: BottleID(rawValue: "winetricks-test"),
            directoryURL: URL(fileURLWithPath: "/tmp/winetricks-test"),
            settings: BottleSettings(),
            isAvailable: true
        )

        let environment = await service.baseEnvironment(for: bottle)
        #expect(environment["WINE"] == "wine")
        #expect(environment["WINEPREFIX"] == "/tmp/winetricks-test")
        #expect(environment["PATH"]?.contains("/Wine/bin") == true)
    }

    private func makeService() -> WinetricksService {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Tests")
        let fileSystem = LocalFileSystem()
        let logger = DefaultAppLogger(subsystem: "com.s3brr.Scotch.Tests", category: "WinetricksServiceTests")
        return WinetricksService(paths: paths, fileSystem: fileSystem, logger: logger)
    }
}

