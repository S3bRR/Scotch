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
        return try await saveSelection(changed)
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
        _ = try await saveSelection(changed)
    }
    public func selectForProgramLaunch(_ bottle: BottleSummary, backend: TranslationBackend, zinkEnabled: Bool) async throws -> (BottleSummary, UpdateLease) {
        let maintenance = try activity.acquireMaintenance()
        defer { withExtendedLifetime(maintenance) {} }
        let saved = try await PlistStore().read(BottleSettings.self, from: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
        guard saved == bottle.settings else { throw RuntimeUpdateError.invalid("Bottle settings changed. Launch the application again.") }
        var changed = bottle
        changed.settings.backend.backend = backend
        changed.settings.backend.glZinkEnabled = zinkEnabled
        let selected = try await saveSelection(changed)
        return (selected, try activity.beginOperation(replacing: maintenance))
    }
    private func saveSelection(_ bottle: BottleSummary) async throws -> BottleSummary {
        var changed = bottle
        changed.settings.fileVersion = BottleSettings.currentFileVersion
        try await PlistStore().write(changed.settings, to: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
        try? BottleEngineMigration.recordSelection(for: changed, paths: paths)
        return changed
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
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink == false else {
            throw RuntimeUpdateError.invalid("Invalid snapshot directory")
        }
        let settings = try PropertyListDecoder().decode(BottleSettings.self, from: Data(contentsOf: source.appending(path: BottleSettings.metadataFileName)))
        // Exchange the existing directories without copying the prefix again.
        guard renamex_np(source.path, bottle.directoryURL.path, UInt32(RENAME_SWAP)) == 0 else {
            throw RuntimeUpdateError.invalid("The recovery copy could not be activated. The original bottle is unchanged.")
        }
        var restored = bottle
        restored.settings = settings
        return restored
    }
}
