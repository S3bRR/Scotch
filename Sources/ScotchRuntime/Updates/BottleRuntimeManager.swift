import Foundation
import Darwin
import ScotchDomain
import ScotchInfrastructure

public actor BottleRuntimeManager {
    private let paths: AppPaths
    private let activity: UpdateActivity
    public init(paths: AppPaths, activity: UpdateActivity = .shared) { self.paths = paths; self.activity = activity }
    nonisolated static func recoveryRoot(for bottle: BottleSummary) -> URL {
        // Keep backups on the prefix's volume so restore can use atomic renames.
        bottle.directoryURL.deletingLastPathComponent().appending(path: ".ScotchPrefixBackups/\(bottle.directoryURL.lastPathComponent)")
    }
    public func switchRuntime(for bottle: BottleSummary, to id: String?) async throws -> BottleSummary {
        let lease = try activity.acquireMaintenance()
        defer { withExtendedLifetime(lease) {} }
        if let id {
            guard ApprovedRuntimeSet.validID(id) else { throw RuntimeUpdateError.invalid("Invalid runtime selection") }
            let selected = paths.forRuntimeSet(id)
            let inspector = RuntimeInstallerService(paths: selected, fileSystem: LocalFileSystem(), logger: DefaultAppLogger(subsystem: paths.bundleIdentifier, category: "RuntimeSwitch"), plistStore: PlistStore(), processRunner: DefaultProcessRunner())
            guard await inspector.isRuntimeInstalled() else { throw RuntimeUpdateError.invalid("The selected runtime is incomplete. The bottle has not been changed.") }
        }
        guard bottle.settings.runtimeSetID != id else { return bottle }
        var changed = bottle
        changed.settings.runtimeSetID = id
        return try await snapshotAndSave(bottle, changed: changed)
    }
    public func switchBackend(for bottle: BottleSummary, settings: BottleSettings) async throws {
        let lease = try activity.acquireMaintenance()
        defer { withExtendedLifetime(lease) {} }
        if [.d3dmetal, .dxmt].contains(settings.backend.backend) {
            try MetalEngineInstallation.verify(in: paths.forBottle(bottle).librariesDirectory)
            try GraphicsSupportInstallation.verify(in: paths.forBottle(bottle).librariesDirectory)
        }
        if settings.backend.backend == .dxmt {
            try MetalEngineInstallation.verifyDXMT(in: paths.forBottle(bottle).librariesDirectory)
        }
        if settings.backend.backend == .d3dmetal {
            try D3DMetalInstallation.verify(at: paths.forBottle(bottle).librariesDirectory.appending(path: "D3DMetal"))
        }
        var changed = bottle
        changed.settings = settings
        _ = try await snapshotAndSave(bottle, changed: changed)
    }
    public func selectForProgramLaunch(_ bottle: BottleSummary, backend: TranslationBackend, zinkEnabled: Bool) async throws -> (BottleSummary, UpdateLease) {
        let maintenance = try activity.acquireMaintenance()
        defer { withExtendedLifetime(maintenance) {} }
        let saved = try await PlistStore().read(BottleSettings.self, from: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
        guard saved == bottle.settings else { throw RuntimeUpdateError.invalid("Bottle settings changed. Launch the application again.") }
        var changed = bottle
        changed.settings.backend.backend = backend
        changed.settings.backend.glZinkEnabled = zinkEnabled
        // Back up before changing either engine or shared graphics DLLs.
        let selected = try await snapshotAndSave(bottle, changed: changed)
        return (selected, try activity.beginOperation(replacing: maintenance))
    }
    private func snapshotAndSave(_ bottle: BottleSummary, changed newBottle: BottleSummary) async throws -> BottleSummary {
        let fm = FileManager.default
        let root = Self.recoveryRoot(for: bottle)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let required = allocatedPrefixBytes(at: bottle.directoryURL)
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available > required + 100_000_000 else { throw RuntimeUpdateError.invalid("Not enough free space to back up this bottle before switching Wine versions.") }
        let snapshot = root.appending(path: "snapshot-\(UUID().uuidString)")
        do {
            try fm.copyItem(at: bottle.directoryURL, to: snapshot)
            let originalData = try Data(contentsOf: snapshot.appending(path: BottleSettings.metadataFileName))
            _ = try PropertyListDecoder().decode(BottleSettings.self, from: originalData)
            // A recovery pointer is written only after the complete copy exists.
            try snapshot.lastPathComponent.data(using: .utf8)!.write(to: root.appending(path: "LatestSnapshot"), options: .atomic)
            var changed = newBottle
            changed.settings.fileVersion = BottleSettings.currentFileVersion
            try await PlistStore().write(changed.settings, to: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
            try? BottleEngineMigration.recordSelection(for: changed, paths: paths)
            return changed
        } catch {
            // Keep complete snapshots if publishing the metadata failed.
            if !fm.fileExists(atPath: snapshot.appending(path: BottleSettings.metadataFileName).path) { try? fm.removeItem(at: snapshot) }
            throw error
        }
    }
    public func hasSnapshot(for bottle: BottleSummary) -> Bool {
        FileManager.default.fileExists(atPath: Self.recoveryRoot(for: bottle).appending(path: "LatestSnapshot").path)
    }
    public func restore(for bottle: BottleSummary) async throws -> BottleSummary {
        let lease = try activity.acquireMaintenance()
        defer { withExtendedLifetime(lease) {} }
        let root = Self.recoveryRoot(for: bottle)
        let name = try String(contentsOf: root.appending(path: "LatestSnapshot"), encoding: .utf8)
        guard name.hasPrefix("snapshot-"), ApprovedRuntimeSet.validID(name) else { throw RuntimeUpdateError.invalid("Invalid snapshot reference") }
        let source = root.appending(path: name)
        let fm = FileManager.default
        // After one atomic exchange this same path holds the replaced prefix.
        // There is no interval in which the original bottle path is missing.
        let staged = root.appending(path: "before-restore-\(UUID().uuidString)")
        var activated = false
        defer { if !activated { try? fm.removeItem(at: staged) } }
        try fm.copyItem(at: source, to: staged)
        let settings = try PropertyListDecoder().decode(BottleSettings.self, from: Data(contentsOf: staged.appending(path: BottleSettings.metadataFileName)))
        guard renamex_np(staged.path, bottle.directoryURL.path, UInt32(RENAME_SWAP)) == 0 else {
            throw RuntimeUpdateError.invalid("The recovery copy could not be activated. The original bottle is unchanged.")
        }
        activated = true
        var restored = bottle
        restored.settings = settings
        return restored
    }
}
