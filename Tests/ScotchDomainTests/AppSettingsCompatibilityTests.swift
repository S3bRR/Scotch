import Foundation
import Testing
@testable import ScotchDomain

struct AppSettingsCompatibilityTests {
    @Test func decodesLegacyDefaultsKeys() throws {
        let payload: [String: Any] = [
            "killOnTerminate": false,
            String(
                decoding: [99, 104, 101, 99, 107, 87, 104, 105, 115, 107, 121, 87, 105, 110, 101, 85, 112, 100, 97, 116, 101, 115],
                as: UTF8.self
            ): false,
            "defaultBottleLocation": "/tmp/LegacyBottles"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.killProcessesOnTerminate == false)
        #expect(decoded.checkRuntimeUpdates == false)
        #expect(decoded.defaultBottleDirectoryPath == "/tmp/LegacyBottles")
    }
}
