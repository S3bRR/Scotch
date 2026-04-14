import Foundation
import Testing
@testable import ScotchDomain

struct BottleCompatibilityTests {
    @Test func decodesLegacyBottleSettingsPayload() throws {
        let legacyPayload: [String: Any] = [
            "fileVersion": [
                "major": 1,
                "minor": 0,
                "patch": 0,
                "build": "",
                "preRelease": ""
            ],
            "info": [
                "name": "Legacy Bottle",
                "pins": [
                    [
                        "name": "Legacy Game",
                        "url": ["relative": "file:///tmp/Legacy%20Game.exe"],
                        "removable": false
                    ]
                ],
                "blocklist": [
                    ["relative": "file:///tmp/blocked.exe"]
                ]
            ],
            "wineConfig": [
                "wineVersion": [
                    "major": 11,
                    "minor": 6,
                    "patch": 0,
                    "build": "",
                    "preRelease": ""
                ],
                "windowsVersion": "win10",
                "enhancedSync": ["msync": [:]],
                "avxEnabled": false
            ],
            "metalConfig": [
                "metalHud": false,
                "metalTrace": false,
                "dxrEnabled": false
            ],
            "backendConfig": [
                "backend": "dxvk",
                "dxvkAsync": true,
                "dxvkHud": ["off": [:]],
                "glZinkEnabled": false,
                "steamBuiltinOpenGL": false
            ],
            "gpuConfig": [
                "spoofPreset": "amdRX7900XTX",
                "customVendorId": 4098,
                "customDeviceId": 29772,
                "customDescription": "AMD Radeon RX 7900 XTX",
                "customVRAM": 24576,
                "deviceIdSalt": 1
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: legacyPayload, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(BottleSettings.self, from: data)

        #expect(decoded.info.name == "Legacy Bottle")
        #expect(decoded.info.pins.first?.name == "Legacy Game")
        #expect(decoded.info.pins.first?.executablePath == "/tmp/Legacy Game.exe")
        #expect(decoded.info.blocklist == ["/tmp/blocked.exe"])
        #expect(decoded.wine.enhancedSync == .msync)
        #expect(decoded.backend.dxvkHud == .off)
        #expect(decoded.backend.backend == .dxvk)

        let encoded = try PropertyListEncoder().encode(decoded)
        let encodedRoot = try #require(PropertyListSerialization.propertyList(from: encoded, options: [], format: nil) as? [String: Any])

        #expect(encodedRoot["wineConfig"] != nil)
        #expect(encodedRoot["backendConfig"] != nil)
        #expect(encodedRoot["gpuConfig"] != nil)
        #expect(encodedRoot["wine"] == nil)
        #expect(encodedRoot["backend"] == nil)
        #expect(encodedRoot["gpu"] == nil)
    }

    @Test func decodesLegacyBottleCatalogPayload() throws {
        let legacyPayload: [String: Any] = [
            "fileVersion": [
                "major": 1,
                "minor": 0,
                "patch": 0,
                "build": "",
                "preRelease": ""
            ],
            "paths": [
                ["relative": "file:///tmp/Bottle-A"],
                ["relative": "file:///tmp/Bottle-B"]
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: legacyPayload, format: .xml, options: 0)
        let decoded = try PropertyListDecoder().decode(BottleCatalog.self, from: data)

        #expect(decoded.bottlePaths == ["/tmp/Bottle-A", "/tmp/Bottle-B"])

        let encoded = try PropertyListEncoder().encode(decoded)
        let encodedRoot = try #require(PropertyListSerialization.propertyList(from: encoded, options: [], format: nil) as? [String: Any])

        #expect(encodedRoot["paths"] != nil)
        #expect(encodedRoot["bottlePaths"] != nil)
    }
}
