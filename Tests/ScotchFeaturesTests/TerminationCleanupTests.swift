import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchFeatures
@testable import ScotchInfrastructure
@testable import ScotchRuntime

@MainActor
struct TerminationCleanupTests {
    @Test func killsBottlesWhenSettingEnabled() async {
        let runtime = SharedMockRuntimeService()
        let bottleRepo = SharedMockBottleRepository()
        let bottles = [makeBottle(id: "b1"), makeBottle(id: "b2"), makeBottle(id: "b3")]
        await bottleRepo.setBottles(bottles)
        let container = makeContainer(
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: "/tmp/a", killProcessesOnTerminate: true),
            runtimeService: runtime,
            bottleRepository: bottleRepo
        )

        await container.performTerminationCleanup(deadline: Date().addingTimeInterval(5))

        let killed = await runtime.killedBottles
        #expect(killed.count == 3)
        #expect(Set(killed.map(\.id.rawValue)) == Set(["b1", "b2", "b3"]))
    }

    @Test func skipsKillWhenSettingDisabled() async {
        let runtime = SharedMockRuntimeService()
        let bottleRepo = SharedMockBottleRepository()
        await bottleRepo.setBottles([makeBottle(id: "b1")])
        let container = makeContainer(
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: "/tmp/a", killProcessesOnTerminate: false),
            runtimeService: runtime,
            bottleRepository: bottleRepo
        )

        await container.performTerminationCleanup(deadline: Date().addingTimeInterval(5))

        let killed = await runtime.killedBottles
        #expect(killed.isEmpty)
    }

    @Test func deadlineCapsTotalDuration() async {
        let runtime = SharedMockRuntimeService()
        await runtime.setKillStall(2)
        let bottleRepo = SharedMockBottleRepository()
        await bottleRepo.setBottles([makeBottle(id: "b1"), makeBottle(id: "b2"), makeBottle(id: "b3")])
        let container = makeContainer(
            settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: "/tmp/a", killProcessesOnTerminate: true),
            runtimeService: runtime,
            bottleRepository: bottleRepo
        )

        let start = Date()
        await container.performTerminationCleanup(deadline: Date().addingTimeInterval(0.5))
        let elapsed = Date().timeIntervalSince(start)

        // First kill stalls 2s, but the deadline (0.5s) is checked before EACH iteration.
        // So at most one bottle gets killed (the first one started before deadline check).
        #expect(elapsed < 4.0, "cleanup ran for \(elapsed)s — deadline not honored")
        let killed = await runtime.killedBottles
        #expect(killed.count <= 1)
    }
}

@MainActor
private func makeContainer(
    settingsStore: AppSettingsStoreProtocol,
    runtimeService: WineRuntimeServiceProtocol,
    bottleRepository: BottleRepositoryProtocol
) -> ScotchContainer {
    let bundleIdentifier = "com.s3brr.Scotch.TerminationTests.\(UUID().uuidString)"
    let paths = AppPaths(bundleIdentifier: bundleIdentifier)
    let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "TerminationTests")
    return ScotchContainer(
        paths: paths,
        logger: logger,
        fileSystem: LocalFileSystem(),
        plistStore: PlistStore(),
        processRunner: DefaultProcessRunner(),
        logStore: LogStore(logsDirectory: paths.logsDirectory),
        runtimeInstaller: SharedMockRuntimeInstaller(),
        runtimeService: runtimeService,
        bottleRepository: bottleRepository,
        settingsStore: settingsStore,
        rosettaService: SharedMockRosettaService(),
        shortcutService: ShortcutService(),
        winetricksService: SharedMockWinetricksService()
    )
}

private func makeBottle(id: String) -> BottleSummary {
    BottleSummary(
        id: BottleID(rawValue: id),
        directoryURL: URL(fileURLWithPath: "/tmp/scotch_termination_\(id)"),
        settings: BottleSettings(),
        isAvailable: true
    )
}
