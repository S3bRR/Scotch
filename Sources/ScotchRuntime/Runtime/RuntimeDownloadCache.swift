import Foundation
import ScotchInfrastructure

/// Only the flat, content-addressed install archives are disposable. Never walk
/// into a bottle, a runtime set, a symlink or another cache (e.g. a signed feed).
public struct RuntimeDownloadCache: Sendable {
    let directory: URL
    public init(paths: AppPaths) { directory = paths.cachesDirectory.appending(path: "RuntimePackages") }

    private func entries() throws -> [(URL, Int64)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        return try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)).compactMap { url in
            let name = url.lastPathComponent.utf8
            guard name.count == 64, name.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
            let info = try url.resourceValues(forKeys: keys)
            guard info.isRegularFile == true, info.isSymbolicLink != true else { return nil }
            return (url, Int64(info.fileSize ?? 0))
        }
    }

    public func size() throws -> Int64 { try entries().reduce(0) { $0 + $1.1 } }

    public func clear(activity: UpdateActivity = .shared) throws -> Int64 {
        let lease = try activity.acquireMaintenance()
        defer { withExtendedLifetime(lease) {} }
        var bytes: Int64 = 0
        for (url, size) in try entries() {
            try FileManager.default.removeItem(at: url)
            bytes += size
        }
        return bytes
    }
}
