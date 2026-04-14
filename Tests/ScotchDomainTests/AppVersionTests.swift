import Testing
@testable import ScotchDomain

struct AppVersionTests {
    @Test func parsesVersionTags() async throws {
        #expect(AppVersion(parsing: "v11.6") == AppVersion(11, 6, 0))
        #expect(AppVersion(parsing: "1.2.3") == AppVersion(1, 2, 3))
        #expect(AppVersion(parsing: "11") == AppVersion(11, 0, 0))
    }

    @Test func comparesVersions() async throws {
        #expect(AppVersion(11, 6, 0) > AppVersion(11, 5, 9))
        #expect(AppVersion(12, 0, 0) > AppVersion(11, 9, 9))
    }
}
