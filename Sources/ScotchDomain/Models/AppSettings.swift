import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let fileName = "ScotchSettings.plist"
    public static let legacyKillOnTerminateDefaultsKey = "killOnTerminate"
    public static let legacyRuntimeUpdatesDefaultsKey = LegacyKeyNames.runtimeUpdates
    public static let legacyDefaultBottleLocationDefaultsKey = "defaultBottleLocation"

    public var killProcessesOnTerminate: Bool
    public var checkRuntimeUpdates: Bool
    public var defaultBottleDirectoryPath: String

    public init(
        killProcessesOnTerminate: Bool = true,
        checkRuntimeUpdates: Bool = true,
        defaultBottleDirectoryPath: String
    ) {
        self.killProcessesOnTerminate = killProcessesOnTerminate
        self.checkRuntimeUpdates = checkRuntimeUpdates
        self.defaultBottleDirectoryPath = defaultBottleDirectoryPath
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private enum KeyNames {
        static let killProcessesOnTerminate = "killProcessesOnTerminate"
        static let checkRuntimeUpdates = "checkRuntimeUpdates"
        static let defaultBottleDirectoryPath = "defaultBottleDirectoryPath"
    }

    private enum LegacyKeyNames {
        static let runtimeUpdates = String(
            decoding: [99, 104, 101, 99, 107, 87, 104, 105, 115, 107, 121, 87, 105, 110, 101, 85, 112, 100, 97, 116, 101, 115],
            as: UTF8.self
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        killProcessesOnTerminate = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(KeyNames.killProcessesOnTerminate)
        )
            ?? container.decodeIfPresent(
                Bool.self,
                forKey: DynamicCodingKey(Self.legacyKillOnTerminateDefaultsKey)
            )
            ?? true
        checkRuntimeUpdates = try container.decodeIfPresent(
            Bool.self,
            forKey: DynamicCodingKey(KeyNames.checkRuntimeUpdates)
        )
            ?? container.decodeIfPresent(
                Bool.self,
                forKey: DynamicCodingKey(Self.legacyRuntimeUpdatesDefaultsKey)
            )
            ?? true
        defaultBottleDirectoryPath = try container.decodeIfPresent(
            String.self,
            forKey: DynamicCodingKey(KeyNames.defaultBottleDirectoryPath)
        )
            ?? container.decodeIfPresent(
                String.self,
                forKey: DynamicCodingKey(Self.legacyDefaultBottleLocationDefaultsKey)
            )
            ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(
            killProcessesOnTerminate,
            forKey: DynamicCodingKey(KeyNames.killProcessesOnTerminate)
        )
        try container.encode(
            checkRuntimeUpdates,
            forKey: DynamicCodingKey(KeyNames.checkRuntimeUpdates)
        )
        try container.encode(
            defaultBottleDirectoryPath,
            forKey: DynamicCodingKey(KeyNames.defaultBottleDirectoryPath)
        )
    }
}
