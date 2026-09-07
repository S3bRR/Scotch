import Foundation
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

public final class ScotchContainer: Sendable {
    public let paths: AppPaths
    public let logger: AppLogger
    public let fileSystem: LocalFileSystem
    public let plistStore: PlistStore
    public let processRunner: ProcessRunner
    public let logStore: LogStore
    public let networkClient: NetworkClient

    public let runtimeInstaller: RuntimeInstallerProtocol
    public let runtimeService: WineRuntimeServiceProtocol
    public let bottleRepository: BottleRepositoryProtocol
    public let settingsStore: AppSettingsStoreProtocol
    public let rosettaService: RosettaServiceProtocol
    public let shortcutService: ShortcutService
    public let winetricksService: WinetricksServiceProtocol
    public let uninstallService: UninstallServiceProtocol
    public let installLedger: InstallLedgerProtocol

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.s3brr.Scotch") {
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "Scotch")
        LegacyDataMigrator(paths: paths, fileSystem: fileSystem, logger: logger).migrateIfNeeded()
        let processRunner = DefaultProcessRunner()
        let logStore = LogStore(logsDirectory: paths.logsDirectory)
        let networkClient = DefaultNetworkClient()
        let environmentAssembler = EnvironmentAssembler(paths: paths)
        let runtimeService = WineRuntimeService(
            paths: paths,
            processRunner: processRunner,
            fileSystem: fileSystem,
            logger: logger,
            logStore: logStore,
            envAssembler: environmentAssembler
        )

        self.paths = paths
        self.logger = logger
        self.fileSystem = fileSystem
        self.plistStore = plistStore
        self.processRunner = processRunner
        self.logStore = logStore
        self.networkClient = networkClient

        self.runtimeService = runtimeService
        self.winetricksService = WinetricksService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            networkClient: networkClient
        )
        self.runtimeInstaller = RuntimeInstallerService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            plistStore: plistStore,
            processRunner: processRunner,
            networkClient: networkClient
        )
        self.bottleRepository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: runtimeService,
            winetricksService: self.winetricksService,
            logger: logger,
            processRunner: processRunner
        )
        self.settingsStore = AppSettingsStore(
            store: plistStore,
            settingsURL: paths.settingsURL,
            defaultBottleDirectory: paths.defaultBottlesDirectory,
            searchURLs: paths.settingsSearchURLs
        )
        self.rosettaService = RosettaService(processRunner: processRunner)
        self.shortcutService = ShortcutService()
        let installLedger = InstallLedgerStore(paths: paths, store: plistStore)
        self.installLedger = installLedger
        self.uninstallService = UninstallService(
            paths: paths,
            fileSystem: fileSystem,
            logger: logger,
            processRunner: processRunner,
            bottleRepository: self.bottleRepository,
            runtimeService: runtimeService,
            installLedger: installLedger
        )
    }

    public init(
        paths: AppPaths,
        logger: AppLogger,
        fileSystem: LocalFileSystem,
        plistStore: PlistStore,
        processRunner: ProcessRunner,
        logStore: LogStore,
        networkClient: NetworkClient = DefaultNetworkClient(),
        runtimeInstaller: RuntimeInstallerProtocol,
        runtimeService: WineRuntimeServiceProtocol,
        bottleRepository: BottleRepositoryProtocol,
        settingsStore: AppSettingsStoreProtocol,
        rosettaService: RosettaServiceProtocol,
        shortcutService: ShortcutService,
        winetricksService: WinetricksServiceProtocol,
        uninstallService: UninstallServiceProtocol,
        installLedger: InstallLedgerProtocol
    ) {
        self.paths = paths
        self.logger = logger
        self.fileSystem = fileSystem
        self.plistStore = plistStore
        self.processRunner = processRunner
        self.logStore = logStore
        self.networkClient = networkClient
        self.runtimeInstaller = runtimeInstaller
        self.runtimeService = runtimeService
        self.bottleRepository = bottleRepository
        self.settingsStore = settingsStore
        self.rosettaService = rosettaService
        self.shortcutService = shortcutService
        self.winetricksService = winetricksService
        self.uninstallService = uninstallService
        self.installLedger = installLedger
    }

    /// Drains running bottles before app termination if the user opted into kill-on-quit.
    /// Returns when all kills are dispatched, or when the deadline is reached — whichever
    /// comes first. Designed to be invoked from `applicationShouldTerminate` and capped so
    /// termination is never blocked indefinitely.
    public func performTerminationCleanup(deadline: Date) async {
        let settings = await settingsStore.loadSettings()
        guard settings.killProcessesOnTerminate else { return }
        let bottles = await bottleRepository.loadBottles()
        for bottle in bottles {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            let killTask = Task {
                await runtimeService.killBottle(bottle, timeout: min(remaining, 1.0))
            }
            await Self.waitForKillTask(killTask, timeout: remaining)
        }
    }

    private static func waitForKillTask(_ task: Task<Void, Never>, timeout: TimeInterval) async {
        guard timeout > 0 else {
            task.cancel()
            return
        }

        await withCheckedContinuation { continuation in
            let gate = OneShotContinuation(continuation)

            Task {
                await task.value
                gate.resume()
            }

            Task {
                try? await Task.sleep(for: .milliseconds(Int((timeout * 1000).rounded(.up))))
                task.cancel()
                gate.resume()
            }
        }
    }
}

private final class OneShotContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
