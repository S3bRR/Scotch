import Foundation
import ScotchDomain
import ScotchInfrastructure

/// Track the selected engine and prevent an unprepared prefix from changing
/// engines while Wine is active.
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
            if existingPrefix && changesEngine && UpdateActivity.shared.hasRunningWineProcesses {
                throw RuntimeUpdateError.invalid("Close Wine processes before changing this bottle’s engine.")
            }
            try recordSelection(for: bottle, paths: paths)
        }
    }
}
