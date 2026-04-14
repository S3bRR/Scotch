import Foundation

public enum WinetricksCategory: String, CaseIterable, Codable, Sendable {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

public struct WinetricksVerb: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public struct WinetricksCategoryListing: Hashable, Sendable {
    public var category: WinetricksCategory
    public var verbs: [WinetricksVerb]

    public init(category: WinetricksCategory, verbs: [WinetricksVerb]) {
        self.category = category
        self.verbs = verbs
    }
}

public enum WinetricksExecutionMode: String, CaseIterable, Sendable {
    case headless
    case terminal
}

public enum WinetricksError: Error, LocalizedError, Sendable {
    case downloadFailed(String)
    case executionFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail):
            "Winetricks download failed: \(detail)"
        case .executionFailed(let detail):
            "Winetricks execution failed: \(detail)"
        case .parseFailed(let detail):
            "Winetricks parse failed: \(detail)"
        }
    }
}

