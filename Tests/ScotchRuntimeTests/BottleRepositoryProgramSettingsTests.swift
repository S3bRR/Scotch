import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct BottleRepositoryProgramSettingsTests {
    @Test func programSettingsRoundtripPersistsToProgramSettingsFolder() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.Tests.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "BottleRepositoryProgramSettingsTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
        defer {
            try? fileSystem.removeItem(at: paths.containerDirectory)
            try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
        }

        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)
        let bottleDirectory = paths.defaultBottlesDirectory.appending(path: "test-bottle")
        try fileSystem.createDirectory(at: bottleDirectory)
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/Program Files/TestGame"))

        let executableURL = bottleDirectory.appending(path: "drive_c/Program Files/TestGame/testgame.exe")
        try Data().write(to: executableURL)

        var settings = BottleSettings()
        settings.info.name = "Test Bottle"
        try await plistStore.write(settings, to: bottleDirectory.appending(path: BottleSettings.metadataFileName))

        let catalog = BottleCatalog(bottlePaths: [bottleDirectory.path(percentEncoded: false)])
        try await plistStore.write(catalog, to: paths.bottleCatalogURL)

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: MockRuntimeService(),
            winetricksService: MockWinetricksService(),
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let bottleID = BottleID(rawValue: "test-bottle")
        let initialPrograms = await repository.refreshPrograms(for: bottleID)
        let initialProgram = try #require(initialPrograms.first)
        #expect(initialProgram.settings.arguments.isEmpty)
        #expect(initialProgram.settings.locale == .auto)

        let updatedSettings = ProgramSettings(
            locale: .french,
            arguments: "--fullscreen",
            environment: ["FOO": "BAR"]
        )
        try await repository.saveProgramSettings(
            updatedSettings,
            forProgramAt: initialProgram.executableURL.path(percentEncoded: false),
            bottleID: bottleID
        )

        let refreshedPrograms = await repository.refreshPrograms(for: bottleID)
        let refreshedProgram = try #require(refreshedPrograms.first)
        #expect(refreshedProgram.settings == updatedSettings)
    }

    @Test func moveBottleRewritesPinAndBlocklistPaths() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.Tests.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "BottleRepositoryProgramSettingsTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)
        let bottleDirectory = paths.defaultBottlesDirectory.appending(path: "move-bottle")
        try fileSystem.createDirectory(at: bottleDirectory)

        let oldExecutable = bottleDirectory.appending(path: "drive_c/Program Files/Game/game.exe")
        let oldBlocked = bottleDirectory.appending(path: "drive_c/Temp/bad.exe")
        try fileSystem.createDirectory(at: oldExecutable.deletingLastPathComponent())
        try fileSystem.createDirectory(at: oldBlocked.deletingLastPathComponent())
        try Data().write(to: oldExecutable)
        try Data().write(to: oldBlocked)

        var settings = BottleSettings()
        settings.info.name = "Move Test"
        settings.info.pins = [
            PinnedProgram(name: "Game", executablePath: oldExecutable.path(percentEncoded: false), removable: true)
        ]
        settings.info.blocklist = [oldBlocked.path(percentEncoded: false)]
        try await plistStore.write(settings, to: bottleDirectory.appending(path: BottleSettings.metadataFileName))

        try await plistStore.write(
            BottleCatalog(bottlePaths: [bottleDirectory.path(percentEncoded: false)]),
            to: paths.bottleCatalogURL
        )

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: MockRuntimeService(),
            winetricksService: MockWinetricksService(),
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let destinationParent = paths.containerDirectory.appending(path: "Moved")
        try fileSystem.createDirectory(at: destinationParent)

        let moved = try await repository.moveBottle(
            id: BottleID(rawValue: "move-bottle"),
            destinationParent: destinationParent
        )

        let newRoot = destinationParent.appending(path: "move-bottle").path(percentEncoded: false)
        let pinPath = try #require(moved.settings.info.pins.first?.executablePath)
        let blockPath = try #require(moved.settings.info.blocklist.first)
        #expect(pinPath.hasPrefix(newRoot))
        #expect(blockPath.hasPrefix(newRoot))
    }

    @Test func exportAndImportRoundtripViaTarArchive() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.Tests.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "BottleRepositoryProgramSettingsTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)
        let bottleDirectory = paths.defaultBottlesDirectory.appending(path: "export-bottle")
        try fileSystem.createDirectory(at: bottleDirectory)
        try await plistStore.write(BottleSettings(), to: bottleDirectory.appending(path: BottleSettings.metadataFileName))
        try await plistStore.write(
            BottleCatalog(bottlePaths: [bottleDirectory.path(percentEncoded: false)]),
            to: paths.bottleCatalogURL
        )

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: MockRuntimeService(),
            winetricksService: MockWinetricksService(),
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let archiveURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tar")
        try? FileManager.default.removeItem(at: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        try await repository.exportBottle(id: BottleID(rawValue: "export-bottle"), destinationArchiveURL: archiveURL)
        #expect(FileManager.default.fileExists(atPath: archiveURL.path(percentEncoded: false)))

        let extractRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: extractRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractRoot) }

        let untar = Process()
        untar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        untar.arguments = ["-xf", archiveURL.path(percentEncoded: false), "-C", extractRoot.path(percentEncoded: false)]
        try untar.run()
        untar.waitUntilExit()
        #expect(untar.terminationStatus == 0)

        let importedBottleURL = extractRoot.appending(path: "export-bottle")
        _ = try await repository.addExistingBottle(at: importedBottleURL)

        let loaded = await repository.loadBottles()
        #expect(loaded.contains(where: { $0.id.rawValue == "export-bottle" }))
    }

    @Test func refreshProgramsCaseInsensitiveDedupPreventsDuplicateSteamPin() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.Tests.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "BottleRepositoryProgramSettingsTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)
        let bottleDirectory = paths.defaultBottlesDirectory.appending(path: "steam-dedup-bottle")
        try fileSystem.createDirectory(at: bottleDirectory)

        let steamExecutableURL = bottleDirectory.appending(path: "drive_c/Program Files (x86)/Steam/Steam.exe")
        try fileSystem.createDirectory(at: steamExecutableURL.deletingLastPathComponent())
        try Data().write(to: steamExecutableURL)

        var settings = BottleSettings()
        settings.info.name = "Steam Dedup"
        settings.info.pins = [
            PinnedProgram(
                name: "Steam",
                executablePath: bottleDirectory
                    .appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
                    .path(percentEncoded: false),
                removable: true
            )
        ]
        try await plistStore.write(settings, to: bottleDirectory.appending(path: BottleSettings.metadataFileName))
        try await plistStore.write(
            BottleCatalog(bottlePaths: [bottleDirectory.path(percentEncoded: false)]),
            to: paths.bottleCatalogURL
        )

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: MockRuntimeService(),
            winetricksService: MockWinetricksService(),
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let programs = await repository.refreshPrograms(for: BottleID(rawValue: "steam-dedup-bottle"))
        let steamPrograms = programs.filter { $0.executableURL.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame }

        #expect(steamPrograms.count == 1)
        #expect(steamPrograms.first?.pinned == true)
    }

    @Test func loadBottlesSkipsCatalogEntriesWithoutMetadata() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.Tests.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "BottleRepositoryProgramSettingsTests")

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }

        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)

        // Real bottle: directory + metadata both present.
        let realBottle = paths.defaultBottlesDirectory.appending(path: "real-bottle")
        try fileSystem.createDirectory(at: realBottle)
        var realSettings = BottleSettings()
        realSettings.info.name = "Real"
        try await plistStore.write(realSettings, to: realBottle.appending(path: BottleSettings.metadataFileName))

        // Orphan #1: catalog path points at a directory that doesn't exist.
        let missingDirectory = paths.defaultBottlesDirectory.appending(path: "gone-bottle")

        // Orphan #2: directory exists but no Metadata.plist (partial-creation crash).
        let partialBottle = paths.defaultBottlesDirectory.appending(path: "partial-bottle")
        try fileSystem.createDirectory(at: partialBottle)

        let catalog = BottleCatalog(bottlePaths: [
            realBottle.path(percentEncoded: false),
            missingDirectory.path(percentEncoded: false),
            partialBottle.path(percentEncoded: false)
        ])
        try await plistStore.write(catalog, to: paths.bottleCatalogURL)

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: MockRuntimeService(),
            winetricksService: MockWinetricksService(),
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let loaded = await repository.loadBottles()
        #expect(loaded.count == 1)
        #expect(loaded.first?.settings.info.name == "Real")
        #expect(loaded.contains { $0.settings.info.name == "Bottle" } == false)
    }
}

private actor MockRuntimeService: WineRuntimeServiceProtocol {
    func runProgram(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runSteam(in bottle: BottleSummary, arguments: [String]) async throws {}
    func runBatchFile(at url: URL, bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String { "" }
    func runWineServer(arguments: [String], bottle: BottleSummary) async throws -> String { "" }
    func syncCompatibilityState(for bottle: BottleSummary) async {}
    func killBottle(_ bottle: BottleSummary) async {}
    func latestLogURL(for bottle: BottleSummary) async -> URL? { nil }
    func makeShellEnvironment(for bottle: BottleSummary) async -> [String: String] { [:] }
    func generateRunCommand(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async -> String { "" }
    func recentLogs(limit: Int) async -> [URL] { [] }
    func readLog(at url: URL, maxCharacters: Int) async -> String { "" }
    func listProcesses(in bottle: BottleSummary) async throws -> [BottleProcessInfo] { [] }
    func killProcess(pid: Int, in bottle: BottleSummary) async throws {}
}

private actor MockWinetricksService: WinetricksServiceProtocol {
    func ensureInstalled() async throws {}
    func parseVerbs() async throws -> [WinetricksCategoryListing] { [] }
    func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String { "" }
    func installCoreFonts(in bottle: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws {}
}
