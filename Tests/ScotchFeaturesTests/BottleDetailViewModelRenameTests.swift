import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchFeatures
@testable import ScotchInfrastructure
@testable import ScotchRuntime

@MainActor
struct BottleDetailViewModelRenameTests {
    @Test func renameBottlePersistsAndUpdatesToast() async {
        let bundleIdentifier = "com.s3brr.Scotch.Rename.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RenameTests")
        let bottleRepo = SharedMockBottleRepository()
        let bottle = BottleSummary(
            id: BottleID(rawValue: "rename-test"),
            directoryURL: paths.containerDirectory.appending(path: "rename-test"),
            settings: BottleSettings(),
            isAvailable: true
        )
        await bottleRepo.setBottles([bottle])

        let container = ScotchContainer(
            paths: paths,
            logger: logger,
            fileSystem: LocalFileSystem(),
            plistStore: PlistStore(),
            processRunner: DefaultProcessRunner(),
            logStore: LogStore(logsDirectory: paths.logsDirectory),
            runtimeInstaller: SharedMockRuntimeInstaller(),
            runtimeService: SharedMockRuntimeService(),
            bottleRepository: bottleRepo,
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
            rosettaService: SharedMockRosettaService(),
            shortcutService: ShortcutService(),
            winetricksService: SharedMockWinetricksService()
        )

        let viewModel = AppViewModel(container: container)
        await viewModel.renameBottle(bottle, to: "Renamed Bottle")

        let saved = await bottleRepo.lastSavedSettings
        #expect(saved?.info.name == "Renamed Bottle")
        #expect(viewModel.toastMessage?.contains("Renamed bottle to Renamed Bottle") == true)
    }

    @Test func renameBottleIgnoresEmptyName() async {
        let bundleIdentifier = "com.s3brr.Scotch.RenameEmpty.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RenameEmptyTests")
        let bottleRepo = SharedMockBottleRepository()
        let bottle = BottleSummary(
            id: BottleID(rawValue: "rename-empty"),
            directoryURL: paths.containerDirectory.appending(path: "rename-empty"),
            settings: BottleSettings(),
            isAvailable: true
        )

        let container = ScotchContainer(
            paths: paths,
            logger: logger,
            fileSystem: LocalFileSystem(),
            plistStore: PlistStore(),
            processRunner: DefaultProcessRunner(),
            logStore: LogStore(logsDirectory: paths.logsDirectory),
            runtimeInstaller: SharedMockRuntimeInstaller(),
            runtimeService: SharedMockRuntimeService(),
            bottleRepository: bottleRepo,
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
            rosettaService: SharedMockRosettaService(),
            shortcutService: ShortcutService(),
            winetricksService: SharedMockWinetricksService()
        )

        let viewModel = AppViewModel(container: container)
        await viewModel.renameBottle(bottle, to: "   ")

        let saved = await bottleRepo.lastSavedSettings
        #expect(saved == nil)
    }
}
