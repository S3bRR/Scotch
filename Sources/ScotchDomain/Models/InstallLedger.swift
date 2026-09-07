import Foundation

public struct InstallLedgerEntry: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var kind: UninstallTarget.Kind
    public var createdAt: Date
    public var note: String?

    public var id: String { path }

    public init(path: String, kind: UninstallTarget.Kind, createdAt: Date = Date(), note: String? = nil) {
        self.path = path
        self.kind = kind
        self.createdAt = createdAt
        self.note = note
    }
}

public struct InstallLedger: Codable, Equatable, Sendable {
    public static let fileName = "InstallLedger.plist"

    public var schemaVersion: Int
    public var entries: [InstallLedgerEntry]

    public init(schemaVersion: Int = 1, entries: [InstallLedgerEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = Self.deduplicated(entries)
    }

    public static func deduplicated(_ entries: [InstallLedgerEntry]) -> [InstallLedgerEntry] {
        var seen = Set<String>()
        var unique: [InstallLedgerEntry] = []
        for entry in entries {
            let key = URL(fileURLWithPath: entry.path).path(percentEncoded: false)
            if seen.insert(key).inserted {
                unique.append(
                    InstallLedgerEntry(path: key, kind: entry.kind, createdAt: entry.createdAt, note: entry.note)
                )
            }
        }
        return unique.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }
}
