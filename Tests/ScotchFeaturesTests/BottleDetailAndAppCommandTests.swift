import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchFeatures
@testable import ScotchInfrastructure
@testable import ScotchRuntime

@MainActor
struct BottleDetailAndAppCommandTests {
    @Test func saveSettingsAppliesWindowsVersionAndPersists() async {
        let harness = makeHarness()
        let viewModel = BottleDetailViewModel(container: harness.container, bottle: harness.bottle)

        var updated = harness.bottle.settings
        updated.wine.windowsVersion = .win11

        await viewModel.saveSettings(updated)

        let wineCalls = await harness.runtime.wineArgumentCalls
        #expect(wineCalls.contains(["winecfg", "-v", WindowsVersion.win11.rawValue]))

        let saved = await harness.bottleRepository.lastSavedSettings
        #expect(saved?.wine.windowsVersion == .win11)
    }

    @Test func saveSettingsSyncsCompatibilityOnBackendChanges() async {
        let harness = makeHarness()
        let viewModel = BottleDetailViewModel(container: harness.container, bottle: harness.bottle)

        var updated = harness.bottle.settings
        updated.backend.backend = .zink

        await viewModel.saveSettings(updated)

        let synced = await harness.runtime.syncedBottles
        #expect(synced.count == 1)
        #expect(synced.first?.settings.backend.backend == .zink)
    }

    @Test func saveSettingsSyncsCompatibilityOnGPUChanges() async {
        let harness = makeHarness()
        let viewModel = BottleDetailViewModel(container: harness.container, bottle: harness.bottle)

        var updated = harness.bottle.settings
        updated.gpu.spoofPreset = .nvidiaRTX4090

        await viewModel.saveSettings(updated)

        let synced = await harness.runtime.syncedBottles
        #expect(synced.count == 1)
        #expect(synced.first?.settings.gpu.spoofPreset == .nvidiaRTX4090)
    }

    @Test func killAllBottlesCommandSignalsEveryBottle() async {
        let harness = makeHarness()
        let appViewModel = AppViewModel(container: harness.container)

        appViewModel.bottles = [
            harness.bottle,
            BottleSummary(
                id: BottleID(rawValue: "test-bottle-2"),
                directoryURL: URL(fileURLWithPath: "/tmp/scotch_v2_bottle_2"),
                settings: harness.bottle.settings,
                isAvailable: true
            )
        ]

        await appViewModel.killAllBottles()

        let killed = await harness.runtime.killedBottles
        #expect(Set(killed.map(\.id.rawValue)) == Set(["test-bottle", "test-bottle-2"]))
        #expect(appViewModel.toastMessage == "Sent kill signal to all bottles.")
    }
}

private struct TestHarness {
    let container: ScotchContainer
    let bottle: BottleSummary
    let runtime: MockRuntimeService
    let bottleRepository: MockBottleRepository
}

@MainActor
private func makeHarness() -> TestHarness {
    let bundleIdentifier = "com.s3brr.Scotch.FeaturesTests.\(UUID().uuidString)"
    let paths = AppPaths(bundleIdentifier: bundleIdentifier)
    let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "ScotchFeaturesTests")
    let fileSystem = LocalFileSystem()
    let plistStore = PlistStore()
    let processRunner = DefaultProcessRunner()
    let logStore = LogStore(logsDirectory: paths.logsDirectory)

    let runtime = MockRuntimeService()
    let bottleRepository = MockBottleRepository()

    let container = ScotchContainer(
        paths: paths,
        logger: logger,
        fileSystem: fileSystem,
        plistStore: plistStore,
        processRunner: processRunner,
        logStore: logStore,
        runtimeInstaller: MockRuntimeInstaller(),
        runtimeService: runtime,
        bottleRepository: bottleRepository,
        settingsStore: MockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
        rosettaService: MockRosettaService(),
        shortcutService: ShortcutService(),
        winetricksService: MockWinetricksService()
    )

    let bottle = BottleSummary(
        id: BottleID(rawValue: "test-bottle"),
        directoryURL: URL(fileURLWithPath: "/tmp/scotch_v2_test_bottle"),
        settings: BottleSettings(),
        isAvailable: true
    )

    return TestHarness(container: container, bottle: bottle, runtime: runtime, bottleRepository: bottleRepository)
}

private actor MockBottleRepository: BottleRepositoryProtocol {
    var lastSavedSettings: BottleSettings?

    func loadBottles() async -> [BottleSummary] { [] }
    func prepareBottle(name: String, windowsVersion: WindowsVersion, containerURL: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func setupWineEnvironment(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary {
        summary
    }
    func installBottleCoreFonts(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary {
        summary
    }
    func addExistingBottle(at directoryURL: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func deleteBottle(id: BottleID, removeFiles: Bool) async throws {}
    func moveBottle(id: BottleID, destinationParent: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func exportBottle(id: BottleID, destinationArchiveURL: URL) async throws {}
    func saveSettings(_ settings: BottleSettings, for id: BottleID) async throws {
        lastSavedSettings = settings
    }
    func saveProgramSettings(_ settings: ProgramSettings, forProgramAt executablePath: String, bottleID: BottleID) async throws {}
    func refreshPrograms(for id: BottleID) async -> [ProgramRecord] { [] }
    func migrationReport() async -> [String] { [] }
    func orphanedCatalogEntries() async -> [String] { [] }
}

private actor MockRuntimeInstaller: RuntimeInstallerProtocol {
    func isRuntimeInstalled() async -> Bool { true }
    func currentManifest() async -> RuntimeManifest? { nil }
    func fetchLatestReleases() async throws -> RuntimeReleases {
        throw RuntimeInstallerError.releaseDiscoveryFailed("Not implemented in mock")
    }
    func downloadAll(releases: RuntimeReleases, progress: (@Sendable (Double) -> Void)?) async throws -> DownloadedRuntimeArchives {
        throw RuntimeInstallerError.downloadFailed("Not implemented in mock")
    }
    func installAll(from archives: DownloadedRuntimeArchives) async throws -> (RuntimeManifest, [OverlayInstallResult]) {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func shouldUpdateRuntime() async -> (Bool, AppVersion) { (false, AppVersion(0, 0, 0)) }
    func overlayDrifts() async -> [OverlayDrift] { [] }
}

private actor MockRuntimeService: WineRuntimeServiceProtocol {
    var wineArgumentCalls: [[String]] = []
    var syncedBottles: [BottleSummary] = []
    var killedBottles: [BottleSummary] = []

    func runProgram(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runSteam(in bottle: BottleSummary, arguments: [String]) async throws {}
    func runBatchFile(at url: URL, bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String {
        wineArgumentCalls.append(arguments)
        return ""
    }
    func runWineServer(arguments: [String], bottle: BottleSummary) async throws -> String { "" }
    func syncCompatibilityState(for bottle: BottleSummary) async {
        syncedBottles.append(bottle)
    }
    func killBottle(_ bottle: BottleSummary) async {
        killedBottles.append(bottle)
    }
    func latestLogURL(for bottle: BottleSummary) async -> URL? { nil }
    func makeShellEnvironment(for bottle: BottleSummary) async -> [String: String] { [:] }
    func generateRunCommand(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async -> String { "" }
    func recentLogs(limit: Int) async -> [URL] { [] }
    func readLog(at url: URL, maxCharacters: Int) async -> String { "" }
    func listProcesses(in bottle: BottleSummary) async throws -> [BottleProcessInfo] { [] }
    func killProcess(pid: Int, in bottle: BottleSummary) async throws {}
}

private actor MockSettingsStore: AppSettingsStoreProtocol {
    private var stored: AppSettings

    init(defaultBottleDirectoryPath: String) {
        stored = AppSettings(defaultBottleDirectoryPath: defaultBottleDirectoryPath)
    }

    func loadSettings() async -> AppSettings { stored }
    func saveSettings(_ settings: AppSettings) async { stored = settings }
}

private actor MockRosettaService: RosettaServiceProtocol {
    func isInstalled() async -> Bool { true }
    func installIfNeeded() async throws -> Bool { true }
}

private actor MockWinetricksService: WinetricksServiceProtocol {
    func ensureInstalled() async throws {}
    func parseVerbs() async throws -> [WinetricksCategoryListing] { [] }
    func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String { "" }
    func installCoreFonts(in bottle: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws {}
}
