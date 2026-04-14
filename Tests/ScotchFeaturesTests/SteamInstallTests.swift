import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchFeatures
@testable import ScotchInfrastructure
@testable import ScotchRuntime

@MainActor
struct SteamInstallTests {
    @Test func installSteamSurfacesHTTPErrorWithoutCrashing() async {
        let bundleIdentifier = "com.s3brr.Scotch.SteamInstall.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "SteamInstallTests")

        let mockNetwork = SharedMockNetworkClient()
        await mockNetwork.setDownloadHandler { request in
            throw NetworkClientError.nonSuccessStatus(url: request.url, status: 503)
        }

        let runtime = SharedMockRuntimeService()
        let bottleRepo = SharedMockBottleRepository()

        let container = ScotchContainer(
            paths: paths,
            logger: logger,
            fileSystem: LocalFileSystem(),
            plistStore: PlistStore(),
            processRunner: DefaultProcessRunner(),
            logStore: LogStore(logsDirectory: paths.logsDirectory),
            networkClient: mockNetwork,
            runtimeInstaller: SharedMockRuntimeInstaller(),
            runtimeService: runtime,
            bottleRepository: bottleRepo,
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
            rosettaService: SharedMockRosettaService(),
            shortcutService: ShortcutService(),
            winetricksService: SharedMockWinetricksService()
        )

        let bottle = BottleSummary(
            id: BottleID(rawValue: "steam-bottle"),
            directoryURL: paths.containerDirectory.appending(path: "steam-bottle"),
            settings: BottleSettings(),
            isAvailable: true
        )

        let viewModel = BottleDetailViewModel(container: container, bottle: bottle)
        await viewModel.installSteam()

        #expect(viewModel.statusMessage?.contains("503") == true)
        #expect(viewModel.steamInstalled == false)
        // Runtime service should not have been called to run the installer.
        let wineCalls = await runtime.wineArgumentCalls
        #expect(wineCalls.isEmpty)
    }

    @Test func installSteamHandlesTransportFailureWithoutCrashing() async {
        let bundleIdentifier = "com.s3brr.Scotch.SteamInstallFail.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "SteamInstallFailTests")

        let mockNetwork = SharedMockNetworkClient()
        await mockNetwork.setDownloadHandler { request in
            throw NetworkClientError.transportFailure(url: request.url, underlying: "DNS failed")
        }

        let container = ScotchContainer(
            paths: paths,
            logger: logger,
            fileSystem: LocalFileSystem(),
            plistStore: PlistStore(),
            processRunner: DefaultProcessRunner(),
            logStore: LogStore(logsDirectory: paths.logsDirectory),
            networkClient: mockNetwork,
            runtimeInstaller: SharedMockRuntimeInstaller(),
            runtimeService: SharedMockRuntimeService(),
            bottleRepository: SharedMockBottleRepository(),
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
            rosettaService: SharedMockRosettaService(),
            shortcutService: ShortcutService(),
            winetricksService: SharedMockWinetricksService()
        )

        let bottle = BottleSummary(
            id: BottleID(rawValue: "steam-bottle"),
            directoryURL: paths.containerDirectory.appending(path: "steam-bottle"),
            settings: BottleSettings(),
            isAvailable: true
        )

        let viewModel = BottleDetailViewModel(container: container, bottle: bottle)
        await viewModel.installSteam()

        #expect(viewModel.statusMessage?.contains("Download failed") == true)
        #expect(viewModel.steamInstalled == false)
    }
}
