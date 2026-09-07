import Foundation

public struct LegacyDataMigrator: Sendable {
    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let logger: AppLogger

    public init(paths: AppPaths, fileSystem: LocalFileSystem, logger: AppLogger) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.logger = logger
    }

    public func migrateIfNeeded() {
        copyFileIfMissing(
            from: paths.legacyContainerDirectory.appending(path: "ScotchSettings.plist"),
            to: paths.settingsURL
        )
        copyFileIfMissing(
            from: paths.legacyContainerDirectory.appending(path: "BottleVM.plist"),
            to: paths.bottleCatalogURL
        )
        copyFileIfMissing(
            from: paths.legacyContainerDirectory.appending(path: "BottleCatalog.plist"),
            to: paths.alternateBottleCatalogURL
        )
        copyDirectoryContentsIfNeeded(from: paths.legacyLogsDirectory, to: paths.logsDirectory)
    }

    private func copyFileIfMissing(from source: URL, to destination: URL) {
        guard fileSystem.fileExists(at: source) else { return }
        if fileSystem.fileExists(at: destination) { return }

        do {
            try fileSystem.createDirectory(at: destination.deletingLastPathComponent())
            try fileSystem.copyItem(at: source, to: destination)
            logger.info("Migrated \(source.lastPathComponent) from legacy location")
        } catch {
            logger.warning("Failed to migrate \(source.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }

    private func copyDirectoryContentsIfNeeded(from source: URL, to destination: URL) {
        guard fileSystem.fileExists(at: source) else { return }

        do {
            try fileSystem.createDirectory(at: destination)
            let items = try fileSystem.contentsOfDirectory(at: source)
            for item in items {
                let target = destination.appending(path: item.lastPathComponent)
                if fileSystem.fileExists(at: target) { continue }
                try fileSystem.copyItem(at: item, to: target)
            }
        } catch {
            logger.warning("Failed to migrate logs from \(source.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }
}
