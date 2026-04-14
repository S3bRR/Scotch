import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct RuntimeParitySmokeTests {
    @Test func bottleCreationRunsWinecfgAndCorefonts() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.RuntimeSmoke.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RuntimeParitySmokeTests")
        let runtime = MockBootstrapRuntimeService()
        let winetricks = MockBootstrapWinetricksService()

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }
        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: runtime,
            winetricksService: winetricks,
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let prepared = try await repository.prepareBottle(
            name: "Smoke Bottle",
            windowsVersion: .win11,
            containerURL: paths.defaultBottlesDirectory
        )
        #expect(prepared.inFlight)
        #expect(!prepared.isAvailable)

        let reported = ProgressRecorder()
        let afterSetup = try await repository.setupWineEnvironment(prepared) { fraction in
            reported.append(fraction)
        }
        #expect(!afterSetup.isAvailable)
        #expect(afterSetup.inFlight)
        #expect(afterSetup.setupProgress == 0.5)

        let final = try await repository.installBottleCoreFonts(afterSetup) { fraction in
            reported.append(fraction)
        }
        #expect(final.isAvailable)
        #expect(!final.inFlight)
        #expect(final.setupProgress == 1.0)
        #expect(!reported.values.isEmpty)

        let wineCalls = await runtime.wineArgumentCalls
        #expect(wineCalls.contains(["winecfg", "-v", WindowsVersion.win11.rawValue]))
        #expect(await winetricks.installCoreFontsCallCount == 1)
    }

    @Test func bottleCreationFailsImmediatelyWhenWinecfgFails() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.RuntimeSmoke.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RuntimeParitySmokeTests")
        let runtime = MockBootstrapRuntimeService(failRunWine: true)
        let winetricks = MockBootstrapWinetricksService()

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }
        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: runtime,
            winetricksService: winetricks,
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let prepared = try await repository.prepareBottle(
            name: "Smoke Bottle",
            windowsVersion: .win11,
            containerURL: paths.defaultBottlesDirectory
        )

        var didThrow = false
        do {
            _ = try await repository.setupWineEnvironment(prepared, progress: nil)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
        #expect(await winetricks.installCoreFontsCallCount == 0)
    }

    @Test func bottleCreationFailsWhenCorefontsFailAndDoesNotPersistCatalogEntry() async throws {
        let bundleIdentifier = "com.s3brr.Scotch.RuntimeSmoke.\(UUID().uuidString)"
        let paths = AppPaths(bundleIdentifier: bundleIdentifier)
        let fileSystem = LocalFileSystem()
        let plistStore = PlistStore()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RuntimeParitySmokeTests")
        let runtime = MockBootstrapRuntimeService()
        let winetricks = MockBootstrapWinetricksService(failInstallCoreFonts: true)

        try? fileSystem.removeItem(at: paths.containerDirectory)
        defer { try? fileSystem.removeItem(at: paths.containerDirectory) }
        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)

        let repository = BottleRepository(
            paths: paths,
            fileSystem: fileSystem,
            plistStore: plistStore,
            runtimeService: runtime,
            winetricksService: winetricks,
            logger: logger,
            processRunner: DefaultProcessRunner()
        )

        let prepared = try await repository.prepareBottle(
            name: "Smoke Bottle",
            windowsVersion: .win11,
            containerURL: paths.defaultBottlesDirectory
        )
        let afterSetup = try await repository.setupWineEnvironment(prepared, progress: nil)

        var didThrow = false
        do {
            _ = try await repository.installBottleCoreFonts(afterSetup, progress: nil)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(await winetricks.installCoreFontsCallCount == 1)
        #expect((await repository.loadBottles()).isEmpty)
    }

    @Test func launchFlowSupportsExeMsiBatSteamAndUnicodePaths() async throws {
        let harness = try RuntimeServiceHarness()
        defer { harness.cleanup() }

        let exeURL = harness.bottle.directoryURL.appending(path: "drive_c/Program Files/Test App/Game.exe")
        let msiURL = harness.bottle.directoryURL.appending(path: "drive_c/Program Files/Test App/Setup.msi")
        let batURL = harness.bottle.directoryURL.appending(path: "drive_c/Program Files/Test App/Launch.bat")
        let unicodeURL = harness.bottle.directoryURL.appending(path: "drive_c/Program Files/テスト/空 白.exe")

        try harness.touch(exeURL)
        try harness.touch(msiURL)
        try harness.touch(batURL)
        try harness.touch(unicodeURL)
        try harness.touch(harness.bottle.directoryURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe"))

        try await harness.runtime.runProgram(at: exeURL, arguments: [], bottle: harness.bottle, extraEnvironment: [:])
        try await harness.runtime.runProgram(at: msiURL, arguments: [], bottle: harness.bottle, extraEnvironment: [:])
        try await harness.runtime.runBatchFile(at: batURL, bottle: harness.bottle, extraEnvironment: [:])
        try await harness.runtime.runProgram(at: unicodeURL, arguments: [], bottle: harness.bottle, extraEnvironment: [:])
        try await harness.runtime.runSteam(in: harness.bottle, arguments: [])

        let specifications = harness.processRunner.recordedSpecifications()

        // EXE/MSI/Unicode/Steam launches should use `open -a Wine.app --args start /unix ...`.
        let openCalls = specifications.filter { $0.executableURL.path(percentEncoded: false) == "/usr/bin/open" }
        #expect(openCalls.count >= 4)
        #expect(openCalls.contains(where: { $0.arguments.contains(exeURL.path(percentEncoded: false)) }))
        #expect(openCalls.contains(where: { $0.arguments.contains(msiURL.path(percentEncoded: false)) }))
        #expect(openCalls.contains(where: { $0.arguments.contains(unicodeURL.path(percentEncoded: false)) }))
        #expect(openCalls.contains(where: { spec in
            spec.arguments.contains(where: { $0.lowercased().hasSuffix("/steam/steam.exe") })
        }))

        // BAT launch should route through wine cmd /c.
        #expect(specifications.contains(where: { $0.arguments.starts(with: ["cmd", "/c", batURL.path(percentEncoded: false)]) }))
    }

    @Test func runProgramSyncsGpuSpoofRegistryAndWritesDXVKConfig() async throws {
        let harness = try RuntimeServiceHarness()
        defer { harness.cleanup() }

        var spoofedSettings = harness.bottle.settings
        spoofedSettings.backend.backend = .dxvk
        spoofedSettings.gpu.spoofPreset = .nvidiaRTX4090
        spoofedSettings.gpu.deviceIdSalt = 0

        let spoofedBottle = BottleSummary(
            id: harness.bottle.id,
            directoryURL: harness.bottle.directoryURL,
            settings: spoofedSettings,
            isAvailable: true
        )

        let exeURL = spoofedBottle.directoryURL.appending(path: "drive_c/Program Files/Test App/Game.exe")
        try harness.touch(exeURL)

        try await harness.runtime.runProgram(at: exeURL, arguments: [], bottle: spoofedBottle, extraEnvironment: [:])

        let specs = harness.processRunner.recordedSpecifications()
        let regAdds = specs.filter { spec in
            spec.executableURL == harness.paths.wineBinaryURL
                && spec.arguments.count >= 6
                && spec.arguments[0] == "reg"
                && spec.arguments[1] == "add"
        }

        #expect(regAdds.contains(where: { $0.arguments.contains("VideoPciVendorID") && $0.arguments.contains("4318") }))
        #expect(regAdds.contains(where: { $0.arguments.contains("VideoPciDeviceID") && $0.arguments.contains("9860") }))
        #expect(regAdds.contains(where: { $0.arguments.contains("VideoMemorySize") && $0.arguments.contains("24576") }))

        let dxvkConfig = spoofedBottle.directoryURL.appending(path: "dxvk.conf")
        let content = try String(contentsOf: dxvkConfig, encoding: .utf8)
        #expect(content.contains("dxgi.customVendorId = 10de"))
        #expect(content.contains("dxgi.customDeviceId = 2684"))
    }
}

private struct RuntimeServiceHarness {
    let paths: AppPaths
    let fileSystem: LocalFileSystem
    let processRunner: RecordingProcessRunner
    let runtime: WineRuntimeService
    let bottle: BottleSummary

    init() throws {
        let bundleIdentifier = "com.s3brr.Scotch.RuntimeServiceHarness.\(UUID().uuidString)"
        paths = AppPaths(bundleIdentifier: bundleIdentifier)
        fileSystem = LocalFileSystem()
        processRunner = RecordingProcessRunner()
        let logger = DefaultAppLogger(subsystem: bundleIdentifier, category: "RuntimeServiceHarness")
        let logStore = LogStore(logsDirectory: paths.logsDirectory)
        let envAssembler = EnvironmentAssembler(paths: paths)
        runtime = WineRuntimeService(
            paths: paths,
            processRunner: processRunner,
            fileSystem: fileSystem,
            logger: logger,
            logStore: logStore,
            envAssembler: envAssembler
        )

        try? fileSystem.removeItem(at: paths.containerDirectory)
        try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
        try fileSystem.createDirectory(at: paths.defaultBottlesDirectory)
        try fileSystem.createDirectory(at: paths.librariesDirectory)
        try fileSystem.createDirectory(at: paths.logsDirectory)

        // Runtime marker files expected by WineRuntimeService.
        try Self.touch(paths.wineBinaryURL, with: fileSystem)
        try Self.touch(paths.wineServerBinaryURL, with: fileSystem)
        try fileSystem.createDirectory(at: paths.wineBundleURL)
        try fileSystem.createDirectory(at: paths.librariesDirectory.appending(path: "DXVK/x64"))
        try fileSystem.createDirectory(at: paths.librariesDirectory.appending(path: "DXVK/x32"))
        try Self.touch(paths.librariesDirectory.appending(path: "DXVK/x64/dxgi.dll"), with: fileSystem)
        try Self.touch(paths.librariesDirectory.appending(path: "DXVK/x32/dxgi.dll"), with: fileSystem)

        let bottleDirectory = paths.defaultBottlesDirectory.appending(path: "smoke-bottle")
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/windows/system32"))
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/windows/syswow64"))
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/Program Files/Test App"))
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/Program Files/テスト"))
        try fileSystem.createDirectory(at: bottleDirectory.appending(path: "drive_c/Program Files (x86)/Steam"))

        bottle = BottleSummary(
            id: BottleID(rawValue: "smoke-bottle"),
            directoryURL: bottleDirectory,
            settings: BottleSettings(),
            isAvailable: true
        )
    }

    func cleanup() {
        try? fileSystem.removeItem(at: paths.containerDirectory)
        try? fileSystem.removeItem(at: paths.applicationSupportDirectory)
    }

    func touch(_ url: URL) throws {
        try fileSystem.createDirectory(at: url.deletingLastPathComponent())
        if !fileSystem.fileExists(at: url) {
            try Data().write(to: url)
        }
    }

    private static func touch(_ url: URL, with fileSystem: LocalFileSystem) throws {
        try fileSystem.createDirectory(at: url.deletingLastPathComponent())
        if !fileSystem.fileExists(at: url) {
            try Data().write(to: url)
        }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class RecordingProcessRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [ProcessSpecification] = []

    func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        record(specification)
        return AsyncStream { continuation in
            continuation.yield(.started)
            continuation.yield(.terminated(0))
            continuation.finish()
        }
    }

    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        record(specification)
        return ""
    }

    func recordedSpecifications() -> [ProcessSpecification] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    private func record(_ specification: ProcessSpecification) {
        lock.lock()
        captured.append(specification)
        lock.unlock()
    }
}

private actor MockBootstrapRuntimeService: WineRuntimeServiceProtocol {
    private let failRunWine: Bool
    var wineArgumentCalls: [[String]] = []

    init(failRunWine: Bool = false) {
        self.failRunWine = failRunWine
    }

    func runProgram(at url: URL, arguments: [String], bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runSteam(in bottle: BottleSummary, arguments: [String]) async throws {}
    func runBatchFile(at url: URL, bottle: BottleSummary, extraEnvironment: [String: String]) async throws {}
    func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String {
        if failRunWine {
            throw RuntimeInstallerError.installFailed("Intentional winecfg failure")
        }
        wineArgumentCalls.append(arguments)
        return ""
    }
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

private actor MockBootstrapWinetricksService: WinetricksServiceProtocol {
    private let failInstallCoreFonts: Bool
    var installCoreFontsCallCount = 0

    init(failInstallCoreFonts: Bool = false) {
        self.failInstallCoreFonts = failInstallCoreFonts
    }

    func ensureInstalled() async throws {}
    func parseVerbs() async throws -> [WinetricksCategoryListing] { [] }
    func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String { "" }
    func installCoreFonts(in bottle: BottleSummary, progress: (@Sendable (Double) -> Void)?) async throws {
        installCoreFontsCallCount += 1
        if failInstallCoreFonts {
            throw RuntimeInstallerError.installFailed("Intentional corefonts failure")
        }
    }
}
