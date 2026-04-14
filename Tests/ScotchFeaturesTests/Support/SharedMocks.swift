import Foundation
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

actor SharedMockNetworkClient: NetworkClient {
    private var dataHandler: (@Sendable (NetworkRequest) async throws -> Data)?
    private var downloadHandler: (@Sendable (NetworkRequest) async throws -> URL)?
    private(set) var capturedRequests: [NetworkRequest] = []

    func setDataHandler(_ handler: @escaping @Sendable (NetworkRequest) async throws -> Data) {
        self.dataHandler = handler
    }
    func setDownloadHandler(_ handler: @escaping @Sendable (NetworkRequest) async throws -> URL) {
        self.downloadHandler = handler
    }

    func data(for request: NetworkRequest) async throws -> Data {
        capturedRequests.append(request)
        guard let handler = dataHandler else {
            throw NetworkClientError.transportFailure(url: request.url, underlying: "no dataHandler set")
        }
        return try await handler(request)
    }

    func download(from request: NetworkRequest) async throws -> URL {
        capturedRequests.append(request)
        guard let handler = downloadHandler else {
            throw NetworkClientError.transportFailure(url: request.url, underlying: "no downloadHandler set")
        }
        return try await handler(request)
    }
}

actor SharedMockBottleRepository: BottleRepositoryProtocol {
    var lastSavedSettings: BottleSettings?
    var bottlesToReturn: [BottleSummary] = []

    func setBottles(_ bottles: [BottleSummary]) { self.bottlesToReturn = bottles }

    func loadBottles() async -> [BottleSummary] { bottlesToReturn }
    func prepareBottle(name: String, windowsVersion: WindowsVersion, containerURL: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func setupWineEnvironment(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary { summary }
    func installBottleCoreFonts(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary { summary }
    func addExistingBottle(at directoryURL: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func deleteBottle(id: BottleID, removeFiles: Bool) async throws {}
    func moveBottle(id: BottleID, destinationParent: URL) async throws -> BottleSummary {
        throw RuntimeInstallerError.installFailed("Not implemented in mock")
    }
    func exportBottle(id: BottleID, destinationArchiveURL: URL) async throws {}
    func saveSettings(_ settings: BottleSettings, for id: BottleID) async throws { lastSavedSettings = settings }
    func saveProgramSettings(_ settings: ProgramSettings, forProgramAt executablePath: String, bottleID: BottleID) async throws {}
    func refreshPrograms(for id: BottleID) async -> [ProgramRecord] { [] }
    func migrationReport() async -> [String] { [] }
    func orphanedCatalogEntries() async -> [String] { [] }
}

actor SharedMockRuntimeInstaller: RuntimeInstallerProtocol {
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

actor SharedMockRuntimeService: WineRuntimeServiceProtocol {
    var wineArgumentCalls: [[String]] = []
    var syncedBottles: [BottleSummary] = []
    var killedBottles: [BottleSummary] = []
    var killStallSeconds: TimeInterval = 0

    func setKillStall(_ seconds: TimeInterval) { self.killStallSeconds = seconds }

    func runProgram(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runSteam(in bottle: BottleSummary, arguments: [String]) async throws {}
    func runBatchFile(at url: URL, bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String {
        wineArgumentCalls.append(arguments); return ""
    }
    func runWineServer(arguments: [String], bottle: BottleSummary) async throws -> String { "" }
    func syncCompatibilityState(for bottle: BottleSummary) async { syncedBottles.append(bottle) }
    func killBottle(_ bottle: BottleSummary) async {
        if killStallSeconds > 0 {
            try? await Task.sleep(for: .seconds(killStallSeconds))
        }
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

actor SharedMockSettingsStore: AppSettingsStoreProtocol {
    private var stored: AppSettings

    init(defaultBottleDirectoryPath: String, killProcessesOnTerminate: Bool = false) {
        var settings = AppSettings(defaultBottleDirectoryPath: defaultBottleDirectoryPath)
        settings.killProcessesOnTerminate = killProcessesOnTerminate
        stored = settings
    }

    func loadSettings() async -> AppSettings { stored }
    func saveSettings(_ settings: AppSettings) async { stored = settings }
}

actor SharedMockRosettaService: RosettaServiceProtocol {
    func isInstalled() async -> Bool { true }
    func installIfNeeded() async throws -> Bool { true }
}

actor SharedMockWinetricksService: WinetricksServiceProtocol {
    func ensureInstalled() async throws {}
    func parseVerbs() async throws -> [WinetricksCategoryListing] { [] }
    func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String { "" }
    func installCoreFonts(in bottle: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws {}
}
