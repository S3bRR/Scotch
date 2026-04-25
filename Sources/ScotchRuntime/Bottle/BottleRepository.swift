import Foundation
import CryptoKit
import ScotchDomain
import ScotchInfrastructure

public actor BottleRepository: BottleRepositoryProtocol {
    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let plistStore: PlistStore
    private let runtimeService: WineRuntimeServiceProtocol
    private let winetricksService: WinetricksServiceProtocol
    private let logger: AppLogger
    private let processRunner: ProcessRunner
    private var migrationEvents: [String] = []

    public init(
        paths: AppPaths,
        fileSystem: LocalFileSystem,
        plistStore: PlistStore,
        runtimeService: WineRuntimeServiceProtocol,
        winetricksService: WinetricksServiceProtocol,
        logger: AppLogger,
        processRunner: ProcessRunner
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.plistStore = plistStore
        self.runtimeService = runtimeService
        self.winetricksService = winetricksService
        self.logger = logger
        self.processRunner = processRunner
    }

    public func loadBottles() async -> [BottleSummary] {
        let catalog = await loadCatalog()
        var summaries: [BottleSummary] = []

        for rawPath in catalog.bottlePaths {
            let directory = URL(fileURLWithPath: rawPath)
            let metadata = directory.appending(path: BottleSettings.metadataFileName)

            // If the metadata file is missing the catalog entry is orphaned
            // (partial creation, manually deleted folder, moved bottle). Skip it
            // so it doesn't surface as a phantom "Bottle" with default settings.
            // The catalog entry stays on disk in case the location is only
            // temporarily unavailable (e.g., an unmounted external drive).
            guard fileSystem.fileExists(at: metadata) else {
                continue
            }

            let settings: BottleSettings
            if let decoded = try? await plistStore.read(BottleSettings.self, from: metadata) {
                settings = decoded
            } else {
                logger.error("Failed to decode metadata for bottle at \(metadata.path(percentEncoded: false)); marking unavailable")
                recordMigrationEvent("Corrupted metadata detected at \(metadata.lastPathComponent) in \(directory.lastPathComponent)")
                var fallback = BottleSettings()
                fallback.info.name = "\(directory.lastPathComponent) (Corrupted Metadata)"
                summaries.append(
                    BottleSummary(
                        id: BottleID(rawValue: directory.lastPathComponent),
                        directoryURL: directory,
                        settings: fallback,
                        isAvailable: false
                    )
                )
                continue
            }

            summaries.append(
                BottleSummary(
                    id: BottleID(rawValue: directory.lastPathComponent),
                    directoryURL: directory,
                    settings: settings,
                    isAvailable: true
                )
            )
        }

        return summaries.sorted { $0.settings.info.name.lowercased() < $1.settings.info.name.lowercased() }
    }

    public func prepareBottle(name: String, windowsVersion: WindowsVersion, containerURL: URL) async throws -> BottleSummary {
        let bottleID = BottleID()
        let bottleDirectory = containerURL.appending(path: bottleID.rawValue)
        try fileSystem.createDirectory(at: bottleDirectory)

        var settings = BottleSettings()
        settings.info.name = name
        settings.wine.windowsVersion = windowsVersion
        settings.gpu.deviceIdSalt = UInt8.random(in: 0...255)

        return BottleSummary(
            id: bottleID,
            directoryURL: bottleDirectory,
            settings: settings,
            isAvailable: false,
            inFlight: true,
            setupProgress: 0.05
        )
    }

    public func setupWineEnvironment(
        _ summary: BottleSummary,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> BottleSummary {
        var working = summary

        _ = try await runtimeService.runWine(
            arguments: ["winecfg", "-v", working.settings.wine.windowsVersion.rawValue],
            bottle: working,
            environment: [:]
        )

        // Disable Windows "Enhance pointer precision" (mouse acceleration) at bottle creation.
        // Applied as a default so new bottles never ship with accel on.
        let mouseAccelDefaults: [(name: String, value: String)] = [
            ("MouseSpeed",      "0"),
            ("MouseThreshold1", "0"),
            ("MouseThreshold2", "0")
        ]
        for entry in mouseAccelDefaults {
            _ = try? await runtimeService.runWine(
                arguments: ["reg", "add", #"HKCU\Control Panel\Mouse"#,
                            "-v", entry.name, "-t", "REG_SZ", "-d", entry.value, "-f"],
                bottle: working,
                environment: [:]
            )
        }

        working.setupProgress = 0.5
        progress?(working.setupProgress)
        return working
    }

    public func installBottleCoreFonts(
        _ summary: BottleSummary,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> BottleSummary {
        var working = summary
        let metadata = working.directoryURL.appending(path: BottleSettings.metadataFileName)

        try await winetricksService.installCoreFonts(in: working) { [progress] fraction in
            let overall = 0.5 + (fraction * 0.5)
            progress?(overall)
        }

        // Write metadata BEFORE publishing the bottle path to the catalog. If
        // the app is killed between these steps, a catalog entry pointing at a
        // directory with no Metadata.plist would surface as a phantom bottle on
        // next launch.
        try await plistStore.write(working.settings, to: metadata)
        try await appendBottlePathToCatalog(working.directoryURL.path(percentEncoded: false))

        working.isAvailable = true
        working.setupProgress = 1.0
        working.inFlight = false
        progress?(working.setupProgress)
        return working
    }

    public func addExistingBottle(at directoryURL: URL) async throws -> BottleSummary {
        let metadata = directoryURL.appending(path: BottleSettings.metadataFileName)
        guard fileSystem.fileExists(at: metadata) else {
            throw RuntimeInstallerError.installFailed("Selected folder is not a valid bottle (missing Metadata.plist)")
        }

        let settings = try await loadSettings(for: directoryURL)
        try await appendBottlePathToCatalog(directoryURL.path(percentEncoded: false))
        return BottleSummary(
            id: BottleID(rawValue: directoryURL.lastPathComponent),
            directoryURL: directoryURL,
            settings: settings,
            isAvailable: true
        )
    }

    public func deleteBottle(id: BottleID, removeFiles: Bool) async throws {
        var catalog = await loadCatalog()
        guard let index = catalog.bottlePaths.firstIndex(where: { URL(fileURLWithPath: $0).lastPathComponent == id.rawValue }) else {
            return
        }

        let path = URL(fileURLWithPath: catalog.bottlePaths[index])

        if removeFiles {
            // Kill any running wine processes bound to this prefix before
            // touching the directory. Skipping this step leaves wineserver and
            // game processes alive against files that are being unlinked under
            // them — they keep running, hold stale state, and can block the
            // removal outright on macOS if any files are exclusively held.
            let killTarget = BottleSummary(
                id: id,
                directoryURL: path,
                settings: BottleSettings(),
                isAvailable: true
            )
            await runtimeService.killBottle(killTarget)

            // Brief grace for wineserver to finish its own cleanup. 500 ms is
            // empirically enough for a quiescent prefix.
            try? await Task.sleep(nanoseconds: 500_000_000)

            if fileSystem.fileExists(at: path) {
                try fileSystem.removeItem(at: path)
            }
        }

        catalog.bottlePaths.remove(at: index)
        try await plistStore.write(catalog, to: paths.bottleCatalogURL)
    }

    public func moveBottle(id: BottleID, destinationParent: URL) async throws -> BottleSummary {
        var catalog = await loadCatalog()
        guard let index = catalog.bottlePaths.firstIndex(where: { URL(fileURLWithPath: $0).lastPathComponent == id.rawValue }) else {
            throw RuntimeInstallerError.installFailed("Bottle not found")
        }

        let currentURL = URL(fileURLWithPath: catalog.bottlePaths[index])
        var settings = try await loadSettings(for: currentURL)
        let originalSettings = settings
        let destination = destinationParent.appending(path: id.rawValue)
        try fileSystem.moveItem(at: currentURL, to: destination)
        do {
            settings.info.pins = settings.info.pins.map { pin in
                var rewritten = pin
                rewritten.executablePath = rewritePath(pin.executablePath, oldRoot: currentURL, newRoot: destination)
                return rewritten
            }
            settings.info.blocklist = settings.info.blocklist.map { path in
                rewritePath(path, oldRoot: currentURL, newRoot: destination)
            }

            let metadata = destination.appending(path: BottleSettings.metadataFileName)
            try await plistStore.write(settings, to: metadata)

            catalog.bottlePaths[index] = destination.path(percentEncoded: false)
            try await plistStore.write(catalog, to: paths.bottleCatalogURL)
            return BottleSummary(id: id, directoryURL: destination, settings: settings, isAvailable: true)
        } catch {
            if fileSystem.fileExists(at: destination), !fileSystem.fileExists(at: currentURL) {
                try? fileSystem.moveItem(at: destination, to: currentURL)
                try? await plistStore.write(
                    originalSettings,
                    to: currentURL.appending(path: BottleSettings.metadataFileName)
                )
            }
            throw error
        }
    }

    public func exportBottle(id: BottleID, destinationArchiveURL: URL) async throws {
        let catalog = await loadCatalog()
        guard let bottlePath = catalog.bottlePaths.first(where: { URL(fileURLWithPath: $0).lastPathComponent == id.rawValue }) else {
            throw RuntimeInstallerError.installFailed("Bottle not found")
        }

        let bottleURL = URL(fileURLWithPath: bottlePath)
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: [
                "-cf",
                destinationArchiveURL.path(percentEncoded: false),
                "-C",
                bottleURL.deletingLastPathComponent().path(percentEncoded: false),
                bottleURL.lastPathComponent
            ],
            displayName: "tar -cf",
            timeout: 30 * 60
        )

        do {
            _ = try await processRunner.captureProcess(spec, outputFileHandle: nil)
        } catch let ProcessRunnerError.nonZeroExit(_, _, output) {
            throw RuntimeInstallerError.installFailed("Bottle export failed: \(output)")
        } catch {
            throw RuntimeInstallerError.installFailed("Bottle export failed: \(error.localizedDescription)")
        }
    }

    public func saveSettings(_ settings: BottleSettings, for id: BottleID) async throws {
        let bottles = await loadBottles()
        guard let bottle = bottles.first(where: { $0.id == id }) else { return }
        let metadata = bottle.directoryURL.appending(path: BottleSettings.metadataFileName)
        try await plistStore.write(settings, to: metadata)
    }

    public func saveProgramSettings(_ settings: ProgramSettings, forProgramAt executablePath: String, bottleID: BottleID) async throws {
        let bottles = await loadBottles()
        guard let bottle = bottles.first(where: { $0.id == bottleID }) else { return }
        let settingsURL = programSettingsURL(for: URL(fileURLWithPath: executablePath), bottleDirectory: bottle.directoryURL)
        if !fileSystem.fileExists(at: settingsURL.deletingLastPathComponent()) {
            try fileSystem.createDirectory(at: settingsURL.deletingLastPathComponent())
        }
        try await plistStore.write(settings, to: settingsURL)
    }

    public func refreshPrograms(for id: BottleID) async -> [ProgramRecord] {
        let bottles = await loadBottles()
        guard let bottle = bottles.first(where: { $0.id == id }) else { return [] }
        return await scanPrograms(in: bottle)
    }

    public func migrationReport() async -> [String] {
        migrationEvents
    }

    public func orphanedCatalogEntries() async -> [String] {
        let catalog = await loadCatalog()
        return catalog.bottlePaths.filter { rawPath in
            let directory = URL(fileURLWithPath: rawPath)
            let metadata = directory.appending(path: BottleSettings.metadataFileName)
            return !fileSystem.fileExists(at: directory) || !fileSystem.fileExists(at: metadata)
        }
    }

    private func scanPrograms(in bottle: BottleSummary) async -> [ProgramRecord] {
        let driveC = bottle.directoryURL.appending(path: "drive_c")
        let programFolders = ["Program Files", "Program Files (x86)"]

        var discovered: [ProgramRecord] = []
        var seen: Set<String> = []
        var updatedSettings = bottle.settings
        var didMutateSettings = false

        let deduplicatedPins = deduplicatePins(updatedSettings.info.pins)
        if deduplicatedPins.count != updatedSettings.info.pins.count {
            updatedSettings.info.pins = deduplicatedPins
            didMutateSettings = true
        }

        let existingPins = updatedSettings.info.pins.filter { pin in
            let executableURL = URL(fileURLWithPath: pin.executablePath)
            return fileSystem.fileExists(at: executableURL)
        }
        if existingPins.count != updatedSettings.info.pins.count {
            updatedSettings.info.pins = existingPins
            didMutateSettings = true
        }

        for folder in programFolders {
            let root = driveC.appending(path: folder)
            guard let enumerator = fileSystem.enumerator(at: root) else { continue }
            while let next = enumerator.nextObject() as? URL {
                guard next.pathExtension.lowercased() == "exe" else { continue }
                let path = next.path(percentEncoded: false)
                let normalizedPath = normalizedProgramPath(path)
                guard !isBlocked(path, blocklist: updatedSettings.info.blocklist), !seen.contains(normalizedPath) else { continue }
                seen.insert(normalizedPath)

                let pin = updatedSettings.info.pins.first(where: { $0.executablePath.caseInsensitiveCompare(path) == .orderedSame })
                let programSettings = await loadProgramSettings(for: next, bottleDirectory: bottle.directoryURL)
                discovered.append(
                    ProgramRecord(
                        executableURL: next,
                        displayName: pin?.name ?? next.deletingPathExtension().lastPathComponent,
                        pinned: pin != nil,
                        settings: programSettings
                    )
                )
            }
        }

        let discoveredStartMenuPrograms = scanStartMenuPrograms(in: bottle.directoryURL)
        for url in discoveredStartMenuPrograms {
            let path = url.path(percentEncoded: false)
            let normalizedPath = normalizedProgramPath(path)
            guard !isBlocked(path, blocklist: updatedSettings.info.blocklist), !seen.contains(normalizedPath) else { continue }
            seen.insert(normalizedPath)

            if !updatedSettings.info.pins.contains(where: { $0.executablePath.caseInsensitiveCompare(path) == .orderedSame }) {
                updatedSettings.info.pins.append(
                    PinnedProgram(
                        name: url.deletingPathExtension().lastPathComponent,
                        executablePath: path,
                        removable: true
                    )
                )
                didMutateSettings = true
            }

            let programSettings = await loadProgramSettings(for: url, bottleDirectory: bottle.directoryURL)
            discovered.append(
                ProgramRecord(
                    executableURL: url,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    pinned: true,
                    discoveredFromStartMenu: true,
                    settings: programSettings
                )
            )
        }

        for pin in updatedSettings.info.pins {
            let normalizedPinPath = normalizedProgramPath(pin.executablePath)
            guard !seen.contains(normalizedPinPath) else { continue }
            let url = URL(fileURLWithPath: pin.executablePath)
            if fileSystem.fileExists(at: url) {
                let programSettings = await loadProgramSettings(for: url, bottleDirectory: bottle.directoryURL)
                discovered.append(
                    ProgramRecord(
                        executableURL: url,
                        displayName: pin.name,
                        pinned: true,
                        settings: programSettings
                    )
                )
                seen.insert(normalizedPinPath)
            }
        }

        if didMutateSettings {
            let metadata = bottle.directoryURL.appending(path: BottleSettings.metadataFileName)
            try? await plistStore.write(updatedSettings, to: metadata)
        }

        return discovered.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned {
                return lhs.pinned && !rhs.pinned
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func deduplicatePins(_ pins: [PinnedProgram]) -> [PinnedProgram] {
        var seen = Set<String>()
        var deduplicated: [PinnedProgram] = []

        for pin in pins {
            let key = normalizedProgramPath(pin.executablePath)
            if seen.insert(key).inserted {
                deduplicated.append(pin)
            }
        }
        return deduplicated
    }

    private func isBlocked(_ executablePath: String, blocklist: [String]) -> Bool {
        blocklist.contains { blocked in
            blocked.caseInsensitiveCompare(executablePath) == .orderedSame
        }
    }

    private func normalizedProgramPath(_ path: String) -> String {
        path.lowercased()
    }

    private func loadProgramSettings(for executableURL: URL, bottleDirectory: URL) async -> ProgramSettings {
        let settingsURL = programSettingsURL(for: executableURL, bottleDirectory: bottleDirectory)

        if let decoded = try? await plistStore.read(ProgramSettings.self, from: settingsURL) {
            return decoded
        }

        let legacyURL = legacyProgramSettingsURL(for: executableURL, bottleDirectory: bottleDirectory)
        if let decoded = try? await plistStore.read(ProgramSettings.self, from: legacyURL) {
            do {
                if !fileSystem.fileExists(at: settingsURL.deletingLastPathComponent()) {
                    try fileSystem.createDirectory(at: settingsURL.deletingLastPathComponent())
                }
                try await plistStore.write(decoded, to: settingsURL)
            } catch {
                logger.warning("Failed to migrate program settings to \(settingsURL.path(percentEncoded: false)): \(error.localizedDescription)")
            }
            return decoded
        }

        let defaults = ProgramSettings()
        do {
            if !fileSystem.fileExists(at: settingsURL.deletingLastPathComponent()) {
                try fileSystem.createDirectory(at: settingsURL.deletingLastPathComponent())
            }
            try await plistStore.write(defaults, to: settingsURL)
        } catch {
            logger.warning("Failed to write default program settings at \(settingsURL.path(percentEncoded: false)): \(error.localizedDescription)")
        }
        return defaults
    }

    private func programSettingsURL(for executableURL: URL, bottleDirectory: URL) -> URL {
        let fileName = Self.programSettingsFileName(forExecutablePath: executableURL.path(percentEncoded: false))

        return bottleDirectory
            .appending(path: "Program Settings")
            .appending(path: fileName)
            .appendingPathExtension("plist")
    }

    static func programSettingsFileName(forExecutablePath executablePath: String) -> String {
        let path = executablePath.lowercased()
        let digest = SHA256.hash(data: Data(path.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let baseName = sanitizedFileName(URL(fileURLWithPath: executablePath).deletingPathExtension().lastPathComponent)

        return "\(baseName)-\(hash)"
    }

    private func legacyProgramSettingsURL(for executableURL: URL, bottleDirectory: URL) -> URL {
        bottleDirectory
            .appending(path: "Program Settings")
            .appending(path: executableURL.lastPathComponent)
            .appendingPathExtension("plist")
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let value = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "program" : value
    }

    private func scanStartMenuPrograms(in bottleDirectory: URL) -> [URL] {
        let startMenuRoots = [
            bottleDirectory
                .appending(path: "drive_c")
                .appending(path: "ProgramData")
                .appending(path: "Microsoft")
                .appending(path: "Windows")
                .appending(path: "Start Menu"),
            bottleDirectory
                .appending(path: "drive_c")
                .appending(path: "users")
                .appending(path: "crossover")
                .appending(path: "AppData")
                .appending(path: "Roaming")
                .appending(path: "Microsoft")
                .appending(path: "Windows")
                .appending(path: "Start Menu")
        ]

        var discovered: [URL] = []
        var seen = Set<String>()

        for root in startMenuRoots {
            guard let enumerator = fileSystem.enumerator(at: root) else { continue }
            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension.lowercased() == "lnk" else { continue }
                guard let programURL = ShellLinkParser.executableURL(from: item, bottleDirectory: bottleDirectory) else { continue }
                guard fileSystem.fileExists(at: programURL) else { continue }
                let normalized = programURL.path(percentEncoded: false).lowercased()
                if seen.insert(normalized).inserted {
                    discovered.append(programURL)
                }
            }
        }

        if !discovered.isEmpty {
            logger.info("Discovered \(discovered.count) program(s) from start menu links in \(bottleDirectory.lastPathComponent)")
        }

        return discovered.sorted {
            $0.path(percentEncoded: false).localizedCaseInsensitiveCompare($1.path(percentEncoded: false)) == .orderedAscending
        }
    }

    private func loadSettings(for bottleDirectory: URL) async throws -> BottleSettings {
        let metadata = bottleDirectory.appending(path: BottleSettings.metadataFileName)
        if fileSystem.fileExists(at: metadata) {
            return try await plistStore.read(BottleSettings.self, from: metadata)
        }

        let defaults = BottleSettings()
        try await plistStore.write(defaults, to: metadata)
        return defaults
    }

    private func loadCatalog() async -> BottleCatalog {
        let primaryURL = paths.bottleCatalogURL
        let alternateURL = paths.alternateBottleCatalogURL

        let primaryCatalog = try? await plistStore.read(BottleCatalog.self, from: primaryURL)
        let alternateCatalog = primaryURL == alternateURL ? nil : (try? await plistStore.read(BottleCatalog.self, from: alternateURL))

        if let primaryCatalog {
            if primaryCatalog.bottlePaths.isEmpty, let alternateCatalog, !alternateCatalog.bottlePaths.isEmpty {
                recordMigrationEvent("Loaded fallback catalog from \(alternateURL.lastPathComponent) because primary catalog was empty")
                try? await plistStore.write(alternateCatalog, to: primaryURL)
                return alternateCatalog
            }
            return primaryCatalog
        }

        if let alternateCatalog {
            recordMigrationEvent("Recovered catalog from \(alternateURL.lastPathComponent)")
            try? await plistStore.write(alternateCatalog, to: primaryURL)
            return alternateCatalog
        }

        let discovered = discoverCatalogFromDefaultDirectory()
        if !discovered.bottlePaths.isEmpty {
            recordMigrationEvent("Discovered \(discovered.bottlePaths.count) bottle(s) from default bottles directory")
        }
        try? await plistStore.write(discovered, to: primaryURL)
        return discovered
    }

    private func appendBottlePathToCatalog(_ path: String) async throws {
        var catalog = await loadCatalog()
        let normalizedPath = URL(fileURLWithPath: path).path(percentEncoded: false)
        if !catalog.bottlePaths.contains(normalizedPath) {
            catalog.bottlePaths.append(normalizedPath)
            try await plistStore.write(catalog, to: paths.bottleCatalogURL)
        }
    }

    private func discoverCatalogFromDefaultDirectory() -> BottleCatalog {
        guard fileSystem.fileExists(at: paths.defaultBottlesDirectory) else {
            return BottleCatalog()
        }

        let candidates = (try? fileSystem.contentsOfDirectory(at: paths.defaultBottlesDirectory)) ?? []
        let discoveredPaths = candidates
            .filter { fileSystem.fileExists(at: $0.appending(path: BottleSettings.metadataFileName)) }
            .map { $0.path(percentEncoded: false) }

        return BottleCatalog(bottlePaths: discoveredPaths)
    }

    private func rewritePath(_ rawPath: String, oldRoot: URL, newRoot: URL) -> String {
        let normalizedRaw = URL(fileURLWithPath: rawPath).path(percentEncoded: false)
        let oldPath = oldRoot.path(percentEncoded: false)
        let newPath = newRoot.path(percentEncoded: false)

        guard normalizedRaw.count >= oldPath.count else {
            return normalizedRaw
        }

        let lowerRaw = normalizedRaw.lowercased()
        let lowerOld = oldPath.lowercased()
        guard lowerRaw.hasPrefix(lowerOld) else {
            return normalizedRaw
        }

        let suffix = String(normalizedRaw.dropFirst(oldPath.count))
        return newPath + suffix
    }

    private func recordMigrationEvent(_ event: String) {
        if !migrationEvents.contains(event) {
            migrationEvents.append(event)
        }
    }
}
