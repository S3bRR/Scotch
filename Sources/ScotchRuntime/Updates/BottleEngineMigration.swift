import Foundation
import ScotchDomain
import ScotchInfrastructure

/// A legacy bottle may already have Metal selected before it has ever used the
/// compatible engine. Protect that first launch as well as explicit UI switches.
enum BottleEngineMigration {
    private static let lock = NSLock()
    private static let marker = ".ScotchWineEngine"

    static func engineID(for bottle: BottleSummary, paths: AppPaths) -> String {
        let selected = paths.forBottle(bottle)
        let engine = selected.usesMetalEngine ? MetalEngineInstallation.version + ":" + GraphicsSupportInstallation.version : "stock-wine-11.16"
        return (bottle.settings.runtimeSetID ?? "legacy") + ":" + engine
    }

    static func recordSelection(for bottle: BottleSummary, paths: AppPaths) throws {
        try Data(engineID(for: bottle, paths: paths).utf8).write(
            to: bottle.directoryURL.appending(path: marker), options: .atomic)
    }

    static func prepare(_ bottle: BottleSummary, paths: AppPaths) throws {
        try lock.withLock {
            let fm = FileManager.default
            let current = try? String(contentsOf: bottle.directoryURL.appending(path: marker), encoding: .utf8)
            let desired = engineID(for: bottle, paths: paths)
            if current == desired { return }
            let existingPrefix = fm.fileExists(atPath: bottle.directoryURL.appending(path: "drive_c").path)
            // Unmarked legacy prefixes already use the stock engine. New empty
            // prefixes have no game data or registry state to migrate.
            let changesEngine = current != nil || paths.forBottle(bottle).usesMetalEngine
            if existingPrefix && changesEngine {
                guard !UpdateActivity.shared.hasRunningWineProcesses else {
                    throw RuntimeUpdateError.invalid("Close Wine processes so Scotch can back up this bottle before changing its engine.")
                }
                let root = BottleRuntimeManager.recoveryRoot(for: bottle)
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                let installationLock = try InstallationLock(at: root.appending(path: "EngineMigration.lock"))
                defer { withExtendedLifetime(installationLock) {} }
                let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard available > allocatedPrefixBytes(at: bottle.directoryURL) + 100_000_000 else {
                    throw RuntimeUpdateError.invalid("Not enough space to back up this bottle before changing its Wine engine.")
                }
                let snapshot = root.appending(path: "snapshot-\(UUID().uuidString)")
                var published = false
                defer { if !published { try? fm.removeItem(at: snapshot) } }
                try fm.copyItem(at: bottle.directoryURL, to: snapshot)
                // Never publish an incomplete or unreadable recovery copy.
                _ = try PropertyListDecoder().decode(BottleSettings.self,
                    from: Data(contentsOf: snapshot.appending(path: BottleSettings.metadataFileName)))
                try Data(snapshot.lastPathComponent.utf8).write(to: root.appending(path: "LatestSnapshot"), options: .atomic)
                published = true
            }
            try recordSelection(for: bottle, paths: paths)
        }
    }
}

func allocatedPrefixBytes(at root: URL) -> Int64 {
    let enumerator = FileManager.default.enumerator(at: root,
        includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey], options: [])
    var total: Int64 = 0
    while let file = enumerator?.nextObject() as? URL {
        if let info = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
            total += Int64(info.totalFileAllocatedSize ?? info.fileAllocatedSize ?? 0)
        }
    }
    return total
}
