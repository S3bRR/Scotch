import Foundation

public struct AppVersion: Codable, Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing raw: String) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let pieces = core.split(separator: ".")
        guard let major = pieces.first.flatMap({ Int($0) }) else {
            return nil
        }
        let minor = pieces.dropFirst().first.flatMap { Int($0) } ?? 0
        let patch = pieces.dropFirst(2).first.flatMap { Int($0) } ?? 0
        self.init(major, minor, patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
