import Foundation
import ScotchDomain

public enum UpdateBackup {
    /// App replacement never touches prefixes. Preserve small user-authored
    /// metadata before new code can run migrations; retain the last 5 snapshots.
    @discardableResult
    public static func metadata(paths: AppPaths) throws -> URL {
        let fm = FileManager.default
        let root = paths.applicationSupportDirectory.appending(path: "UpdateBackups")
        let destination = root.appending(path: "metadata-\(UUID().uuidString)")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var locations: [String: String] = [:]
        var files = paths.catalogSearchURLs + paths.settingsSearchURLs
        for catalogURL in paths.catalogSearchURLs where fm.fileExists(atPath: catalogURL.path) {
            guard let data = try? Data(contentsOf: catalogURL), let catalog = try? PropertyListDecoder().decode(BottleCatalog.self, from: data) else { continue }
            for raw in catalog.bottlePaths {
                let bottle = URL(fileURLWithPath: raw)
                files.append(bottle.appending(path: BottleSettings.metadataFileName))
                if let preferences = try? fm.contentsOfDirectory(at: bottle.appending(path: "Program Settings"), includingPropertiesForKeys: nil) {
                    files += preferences.filter { $0.pathExtension == "plist" }
                }
                // Program preferences are also small; no game files are copied.
                if let items = try? fm.contentsOfDirectory(at: bottle, includingPropertiesForKeys: nil) {
                    files += items.filter { $0.pathExtension == "plist" }
                }
            }
        }
        do {
            for source in Set(files) where fm.fileExists(atPath: source.path) {
                let name = "\(locations.count)-\(source.lastPathComponent)"
                try fm.copyItem(at: source, to: destination.appending(path: name))
                locations[name] = source.path
            }
            try PropertyListEncoder().encode(locations).write(to: destination.appending(path: "Locations.plist"), options: .atomic)
            let snapshots = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]).filter { $0.lastPathComponent.hasPrefix("metadata-") }
                .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            for old in snapshots.dropFirst(5) { try? fm.removeItem(at: old) }
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
}
