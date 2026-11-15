import Foundation
import CryptoKit
import ScotchDomain

/// Shared by GUI, CLI and launch-time selection. An unreadable existing profile
/// is an error, never an invitation to replace it with defaults.
public enum ProgramSettingsFiles {
    public static func fileName(for path: String) -> String {
        let digest = SHA256.hash(data: Data(path.lowercased().utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let name = String(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? "program" : name)-\(hash)"
    }
    public static func url(for executable: URL, in bottle: URL) -> URL {
        bottle.appending(path: "Program Settings/\(fileName(for: executable.path)).plist")
    }
    public static func load(for executable: URL, in bottle: URL) throws -> ProgramSettings {
        let modern = url(for: executable, in: bottle)
        let legacy = bottle.appending(path: "Program Settings/\(executable.lastPathComponent).plist")
        for file in [modern, legacy] where FileManager.default.fileExists(atPath: file.path) {
            return try PropertyListDecoder().decode(ProgramSettings.self, from: Data(contentsOf: file))
        }
        return ProgramSettings()
    }
    public static func save(_ settings: ProgramSettings, for executable: URL, in bottle: URL) async throws {
        _ = try load(for: executable, in: bottle)
        try await PlistStore().write(settings, to: url(for: executable, in: bottle))
    }
}
