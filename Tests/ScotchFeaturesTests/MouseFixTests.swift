import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchFeatures
@testable import ScotchInfrastructure
@testable import ScotchRuntime

@MainActor
struct MouseFixTests {
    @Test func enableWritesTrimmedBundle() async {
        let harness = makeHarness()
        let viewModel = BottleDetailViewModel(container: harness.container, bottle: harness.bottle)

        await viewModel.setMouseFix(true)

        let calls = await harness.runtime.wineArgumentCalls
        // Six writes total — no DLL overrides, no confinement defaults.
        let writeCalls = calls.filter { $0.first == "reg" && $0[safe: 1] == "add" }
        #expect(writeCalls.count == 6)

        let valueNames = writeCalls.compactMap { args -> String? in
            guard let idx = args.firstIndex(of: "-v"), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        #expect(Set(valueNames) == Set([
            "MouseWarpOverride",
            "UsePreciseScrolling",
            "MouseSensitivity",
            "MouseSpeed",
            "MouseThreshold1",
            "MouseThreshold2"
        ]))

        // MouseWarpOverride is force, not disable.
        let warpCall = writeCalls.first { args in
            args.contains("MouseWarpOverride")
        }
        #expect(warpCall?.contains("force") == true)

        #expect(viewModel.statusMessage == "Mouse fix enabled.")
    }

    @Test func disableRemovesOverridesButPinsAccelerationOff() async {
        let harness = makeHarness()
        let viewModel = BottleDetailViewModel(container: harness.container, bottle: harness.bottle)

        await viewModel.setMouseFix(false)

        let calls = await harness.runtime.wineArgumentCalls
        let writeCalls = calls.filter { $0.first == "reg" && $0[safe: 1] == "add" }
        let deleteCalls = calls.filter { $0.first == "reg" && $0[safe: 1] == "delete" }

        #expect(writeCalls.count == 3)
        let writtenNames = writeCalls.compactMap { args -> String? in
            guard let idx = args.firstIndex(of: "-v"), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        #expect(Set(writtenNames) == Set([
            "MouseSpeed",
            "MouseThreshold1",
            "MouseThreshold2"
        ]))

        #expect(deleteCalls.count == 3)
        let deletedNames = deleteCalls.compactMap { args -> String? in
            guard let idx = args.firstIndex(of: "-v"), idx + 1 < args.count else { return nil }
            return args[idx + 1]
        }
        #expect(Set(deletedNames) == Set([
            "MouseWarpOverride",
            "UsePreciseScrolling",
            "MouseSensitivity"
        ]))

        #expect(viewModel.statusMessage == "Mouse fix disabled. Acceleration remains off.")
    }
}

@MainActor
private func makeHarness() -> (container: ScotchContainer, bottle: BottleSummary, runtime: SharedMockRuntimeService) {
    let bundleIdentifier = "com.s3brr.Scotch.MouseFixTests.\(UUID().uuidString)"
    let paths = AppPaths(bundleIdentifier: bundleIdentifier)
    let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "MouseFixTests")
    let runtime = SharedMockRuntimeService()

    let container = ScotchContainer(
        paths: paths,
        logger: logger,
        fileSystem: LocalFileSystem(),
        plistStore: PlistStore(),
        processRunner: DefaultProcessRunner(),
        logStore: LogStore(logsDirectory: paths.logsDirectory),
        runtimeInstaller: SharedMockRuntimeInstaller(),
        runtimeService: runtime,
        bottleRepository: SharedMockBottleRepository(),
        settingsStore: SharedMockSettingsStore(defaultBottleDirectoryPath: paths.defaultBottlesDirectory.path(percentEncoded: false)),
        rosettaService: SharedMockRosettaService(),
        shortcutService: ShortcutService(),
        winetricksService: SharedMockWinetricksService()
    )

    let bottle = BottleSummary(
        id: BottleID(rawValue: "mouse-fix-test"),
        directoryURL: paths.containerDirectory.appending(path: "mouse-fix-test"),
        settings: BottleSettings(),
        isAvailable: true
    )

    return (container, bottle, runtime)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
