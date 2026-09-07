import Foundation

public enum RuntimeInstallerError: Error, LocalizedError, Sendable {
    case invalidURL
    case releaseDiscoveryFailed(String)
    case missingAsset(String)
    case downloadFailed(String)
    case extractionFailed(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .releaseDiscoveryFailed(let message):
            "Release discovery failed: \(message)"
        case .missingAsset(let message):
            "Missing release asset: \(message)"
        case .downloadFailed(let message):
            "Download failed: \(message)"
        case .extractionFailed(let message):
            "Extraction failed: \(message)"
        case .installFailed(let message):
            "Install failed: \(message)"
        }
    }
}

public protocol BottleRepositoryProtocol: Sendable {
    func loadBottles() async -> [BottleSummary]
    func prepareBottle(name: String, windowsVersion: WindowsVersion, containerURL: URL) async throws -> BottleSummary
    func setupWineEnvironment(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary
    func installBottleCoreFonts(_ summary: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws -> BottleSummary
    func addExistingBottle(at directoryURL: URL) async throws -> BottleSummary
    func deleteBottle(id: BottleID, removeFiles: Bool) async throws
    func moveBottle(id: BottleID, destinationParent: URL) async throws -> BottleSummary
    func exportBottle(id: BottleID, destinationArchiveURL: URL) async throws
    func saveSettings(_ settings: BottleSettings, for id: BottleID) async throws
    func saveProgramSettings(_ settings: ProgramSettings, forProgramAt executablePath: String, bottleID: BottleID) async throws
    func refreshPrograms(for id: BottleID) async -> [ProgramRecord]
    func migrationReport() async -> [String]
    func orphanedCatalogEntries() async -> [String]
}

public protocol RuntimeInstallerProtocol: Sendable {
    func isRuntimeInstalled() async -> Bool
    func currentManifest() async -> RuntimeManifest?
    func fetchLatestReleases() async throws -> RuntimeReleases
    func downloadAll(releases: RuntimeReleases, progress: (@Sendable (Double) -> Void)?) async throws -> DownloadedRuntimeArchives
    func installAll(from archives: DownloadedRuntimeArchives) async throws -> (RuntimeManifest, [OverlayInstallResult])
    func shouldUpdateRuntime() async -> (Bool, AppVersion)
    func overlayDrifts() async -> [OverlayDrift]
}

public protocol WineRuntimeServiceProtocol: Sendable {
    func prepareBottleForLaunch(_ bottle: BottleSummary) async throws
    func runProgram(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async throws
    func runSteam(in bottle: BottleSummary, arguments: [String]) async throws
    func runBatchFile(at url: URL, bottle: BottleSummary, extraEnvironment: [String: String]) async throws
    func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String
    func runWineServer(arguments: [String], bottle: BottleSummary) async throws -> String
    func syncCompatibilityState(for bottle: BottleSummary) async
    func killBottle(_ bottle: BottleSummary, timeout: TimeInterval?) async
    func latestLogURL(for bottle: BottleSummary) async -> URL?
    func makeShellEnvironment(for bottle: BottleSummary) async -> [String: String]
    func generateRunCommand(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async -> String
    func recentLogs(limit: Int) async -> [URL]
    func readLog(at url: URL, maxCharacters: Int) async -> String
    func listProcesses(in bottle: BottleSummary) async throws -> [BottleProcessInfo]
    func killProcess(pid: Int, in bottle: BottleSummary) async throws
}

public extension WineRuntimeServiceProtocol {
    func killBottle(_ bottle: BottleSummary) async {
        await killBottle(bottle, timeout: nil)
    }
}

public protocol AppSettingsStoreProtocol: Sendable {
    func loadSettings() async -> AppSettings
    func saveSettings(_ settings: AppSettings) async
}

public protocol RosettaServiceProtocol: Sendable {
    func isInstalled() async -> Bool
    func installIfNeeded() async throws -> Bool
}

public protocol WinetricksServiceProtocol: Sendable {
    func ensureInstalled() async throws
    func parseVerbs() async throws -> [WinetricksCategoryListing]
    func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String
    func installCoreFonts(in bottle: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws
}

public protocol UninstallServiceProtocol: Sendable {
    func preview(includeBottles: Bool, includeAppBundle: Bool) async -> UninstallPlan
    func perform(_ plan: UninstallPlan) async throws -> UninstallResult
}
