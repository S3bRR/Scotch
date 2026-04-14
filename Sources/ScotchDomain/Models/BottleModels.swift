import Foundation

public struct BottleID: Hashable, Codable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }
}

public struct BottleSummary: Identifiable, Equatable, Sendable {
    public var id: BottleID
    public var directoryURL: URL
    public var settings: BottleSettings
    public var isAvailable: Bool
    public var inFlight: Bool
    public var setupProgress: Double
    public var setupErrorMessage: String?

    public init(
        id: BottleID,
        directoryURL: URL,
        settings: BottleSettings,
        isAvailable: Bool,
        inFlight: Bool = false,
        setupProgress: Double = 0,
        setupErrorMessage: String? = nil
    ) {
        self.id = id
        self.directoryURL = directoryURL
        self.settings = settings
        self.isAvailable = isAvailable
        self.inFlight = inFlight
        self.setupProgress = setupProgress
        self.setupErrorMessage = setupErrorMessage
    }
}

public enum ProgramLocale: String, Codable, CaseIterable, Sendable {
    case auto = ""
    case german = "de_DE.UTF-8"
    case english = "en_US"
    case spanish = "es_ES.UTF-8"
    case french = "fr_FR.UTF-8"
    case italian = "it_IT.UTF-8"
    case japanese = "ja_JP.UTF-8"
    case korean = "ko_KR.UTF-8"
    case russian = "ru_RU.UTF-8"
    case ukrainian = "uk_UA.UTF-8"
    case thai = "th_TH.UTF-8"
    case chineseSimplified = "zh_CN.UTF-8"
    case chineseTraditional = "zh_TW.UTF-8"

    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .german: "Deutsch"
        case .english: "English"
        case .spanish: "Espanol"
        case .french: "Francais"
        case .italian: "Italiano"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .russian: "Russian"
        case .ukrainian: "Ukrainian"
        case .thai: "Thai"
        case .chineseSimplified: "Chinese (Simplified)"
        case .chineseTraditional: "Chinese (Traditional)"
        }
    }
}

public struct ProgramSettings: Codable, Equatable, Hashable, Sendable {
    public var locale: ProgramLocale
    public var arguments: String
    public var environment: [String: String]

    public init(locale: ProgramLocale = .auto, arguments: String = "", environment: [String: String] = [:]) {
        self.locale = locale
        self.arguments = arguments
        self.environment = environment
    }

    private enum CodingKeys: String, CodingKey {
        case locale
        case arguments
        case environment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let localeRaw = try container.decodeIfPresent(String.self, forKey: .locale) ?? ""
        locale = ProgramLocale(rawValue: localeRaw) ?? .auto
        arguments = try container.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(locale.rawValue, forKey: .locale)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(environment, forKey: .environment)
    }

    public func parsedArguments() -> [String] {
        parseProgramArgumentString(arguments)
    }

    public func effectiveEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var merged = environment
        if locale != .auto {
            merged["LC_ALL"] = locale.rawValue
        }
        merged.merge(extra, uniquingKeysWith: { _, new in new })
        return merged
    }
}

public struct ProgramRecord: Hashable, Sendable, Identifiable {
    public var id: String { executableURL.path(percentEncoded: false) }
    public var executableURL: URL
    public var displayName: String
    public var pinned: Bool
    public var discoveredFromStartMenu: Bool
    public var settings: ProgramSettings

    public init(
        executableURL: URL,
        displayName: String,
        pinned: Bool,
        discoveredFromStartMenu: Bool = false,
        settings: ProgramSettings = ProgramSettings()
    ) {
        self.executableURL = executableURL
        self.displayName = displayName
        self.pinned = pinned
        self.discoveredFromStartMenu = discoveredFromStartMenu
        self.settings = settings
    }
}

public struct BottleProcessInfo: Hashable, Sendable, Identifiable {
    public var id: Int
    public var pid: Int
    public var processName: String

    public init(pid: Int, processName: String) {
        self.id = pid
        self.pid = pid
        self.processName = processName
    }
}

private func parseProgramArgumentString(_ input: String) -> [String] {
    var arguments: [String] = []
    var current = ""
    var inSingleQuote = false
    var inDoubleQuote = false
    var escaping = false

    for character in input {
        if escaping {
            current.append(character)
            escaping = false
            continue
        }

        if character == "\\" && !inSingleQuote {
            escaping = true
            continue
        }

        if character == "\"" && !inSingleQuote {
            inDoubleQuote.toggle()
            continue
        }

        if character == "'" && !inDoubleQuote {
            inSingleQuote.toggle()
            continue
        }

        if character.isWhitespace && !inSingleQuote && !inDoubleQuote {
            if !current.isEmpty {
                arguments.append(current)
                current.removeAll(keepingCapacity: true)
            }
            continue
        }

        current.append(character)
    }

    if escaping {
        current.append("\\")
    }

    if !current.isEmpty {
        arguments.append(current)
    }
    return arguments
}

public struct BottleCatalog: Codable, Sendable {
    public static let fileName = "BottleVM.plist"
    public static let alternateFileName = "BottleCatalog.plist"
    public static let version = AppVersion(1, 0, 0)

    public var fileVersion: AppVersion
    public var bottlePaths: [String]

    public init(fileVersion: AppVersion = version, bottlePaths: [String] = []) {
        self.fileVersion = fileVersion
        self.bottlePaths = Self.deduplicated(bottlePaths.map(Self.normalizedPath))
    }

    private enum CodingKeys: String, CodingKey {
        case fileVersion
        case bottlePaths
        case legacyPaths = "paths"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileVersion = (try? container.decode(AppVersion.self, forKey: .fileVersion)) ?? Self.version

        if let modern = try? container.decode([String].self, forKey: .bottlePaths) {
            bottlePaths = Self.deduplicated(modern.map(Self.normalizedPath))
            return
        }

        if let legacyURLs = try? container.decode([URL].self, forKey: .legacyPaths) {
            bottlePaths = Self.deduplicated(legacyURLs.map { $0.path(percentEncoded: false) })
            return
        }

        if let legacyStrings = try? container.decode([String].self, forKey: .legacyPaths) {
            bottlePaths = Self.deduplicated(legacyStrings.map(Self.normalizedPath))
            return
        }

        bottlePaths = []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalized = Self.deduplicated(bottlePaths.map(Self.normalizedPath))

        try container.encode(fileVersion, forKey: .fileVersion)
        try container.encode(normalized, forKey: .bottlePaths)
        try container.encode(normalized.map { URL(fileURLWithPath: $0) }, forKey: .legacyPaths)
    }

    private static func normalizedPath(_ raw: String) -> String {
        if let url = URL(string: raw), url.isFileURL {
            return url.path(percentEncoded: false)
        }
        return raw
    }

    private static func deduplicated(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                result.append(path)
            }
        }

        return result
    }
}
