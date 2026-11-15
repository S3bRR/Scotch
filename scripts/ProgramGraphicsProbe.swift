import Foundation
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

@main struct ProgramGraphicsProbe {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchGraphicsSelection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exe = root.appending(path: "game.exe")
        try pe(imports: ["D3D12.dll"]).write(to: exe)
        let dx12 = ExecutableGraphicsInspector.inspect(exe)
        try check(dx12.architecture == .x64 && dx12.apis == [.d3d12] && !dx12.limited, "64-bit DirectX 12 import inspection")
        let firstHash = dx12.fingerprint
        try pe(imports: ["OPENGL32.dll"], x64: false, delayed: true).write(to: exe)
        let gl = ExecutableGraphicsInspector.inspect(exe)
        try check(gl.architecture == .x86 && gl.apis == [.openGL] && !gl.limited, "32-bit delay imports")
        try check(gl.fingerprint != firstHash, "Executable changes invalidate identification")
        try pe(imports: ["d3d12.dll", "unknown-engine.dll"]).write(to: exe)
        try check(ExecutableGraphicsInspector.inspect(exe).limited, "Unresolved non-platform dependencies cannot make a high-confidence choice")
        try pe(imports: ["engine.dll"]).write(to: exe)
        try pe(imports: ["opengl32.dll"]).write(to: root.appending(path: "engine.dll"))
        try check(ExecutableGraphicsInspector.inspect(exe).apis == [.openGL], "Adjacent engine DLL dependency")
        try pe(imports: ["d3d11.dll"]).write(to: root.appending(path: "engine.dll"))
        try check(ExecutableGraphicsInspector.inspect(exe).apis == [.d3d11], "Changed dependency is inspected again")
        try FileManager.default.removeItem(at: root.appending(path: "engine.dll"))
        var corrupt = pe(imports: ["opengl32.dll"])
        put(0xfffffff0, at: 0x300 + 12, data: &corrupt)
        try corrupt.write(to: exe)
        try check(ExecutableGraphicsInspector.inspect(exe).limited, "Out-of-range name RVA rejected")
        try Data([0x4d, 0x5a]).write(to: exe)
        try check(ExecutableGraphicsInspector.inspect(exe).limited, "Truncated header handled")

        var paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.GraphicsSelectionProbe.\(UUID().uuidString)")
        paths.runtimeDirectoryOverride = root.appending(path: "Libraries")
        let wine = paths.wineBinaryURL
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test fixture — never executed".utf8).write(to: wine)
        let bottleDir = root.appending(path: "Bottle")
        try FileManager.default.createDirectory(at: bottleDir, withIntermediateDirectories: true)
        var bottle = BottleSummary(id: BottleID(), directoryURL: bottleDir, settings: BottleSettings(), isAvailable: true)
        try await PlistStore().write(bottle.settings, to: bottleDir.appending(path: BottleSettings.metadataFileName))
        let sentinel = bottleDir.appending(path: "save.dat")
        try Data("preserved game save".utf8).write(to: sentinel)
        let activity = UpdateActivity(processCheck: { false })
        let manager = ProgramGraphicsManager(paths: paths, activity: activity, availabilityCheck: { _, _, _ in nil })
        try check(bottle.settings.backend.automatic, "New bottles default to Auto")
        let legacyData = try PropertyListSerialization.data(fromPropertyList: ["backend": "dxmt"], format: .xml, options: 0)
        let legacy = try PropertyListDecoder().decode(BottleBackendConfig.self, from: legacyData)
        try check(!legacy.automatic && legacy.backend == .dxmt, "Legacy explicit renderer stays manual")
        let roundTrip = try PropertyListDecoder().decode(BottleSettings.self, from: PropertyListEncoder().encode(bottle.settings))
        try check(roundTrip.backend.automatic, "Bottle Auto persists across relaunch")
        let inherited = manager.recommend(dx12, executable: exe, bottle: bottle, settings: ProgramSettings())
        try check(inherited.usesAuto && inherited.automatic && inherited.backend == .d3dmetal, "Default program inherits bottle Auto")
        var manualBottle = bottle; manualBottle.settings.backend.automatic = false
        try check(!manager.recommend(dx12, executable: exe, bottle: manualBottle, settings: ProgramSettings()).usesAuto, "Manual bottle does not enable Auto")
        try pe(imports: ["d3d12.dll"]).write(to: exe)
        try await PlistStore().write(manualBottle.settings, to: bottleDir.appending(path: BottleSettings.metadataFileName))
        do {
            let manualLaunch = try await manager.prepareLaunch(exe, bottle: manualBottle)
            try check(manualLaunch.bottle.settings.backend.backend == .dxvk && manualLaunch.choice == nil, "Manual bottle was overridden by inherited Auto")
            withExtendedLifetime(manualLaunch.lease) {}
        }
        try await PlistStore().write(bottle.settings, to: bottleDir.appending(path: BottleSettings.metadataFileName))

        // Exercise launch-time inheritance with no explicit application Auto setting.
        try pe(imports: ["d3d12.dll"]).write(to: exe)
        do {
            let inheritedLaunch = try await manager.prepareLaunch(exe, bottle: bottle)
            try check(inheritedLaunch.bottle.settings.backend.backend == .d3dmetal && inheritedLaunch.bottle.settings.backend.automatic, "Inherited Auto selects a renderer without disabling the policy")
            bottle = inheritedLaunch.bottle
            withExtendedLifetime(inheritedLaunch.lease) {}
        }
        var settings = ProgramSettings(); settings.graphicsMode = .automatic
        let rec = ProgramGraphicsManager(paths: paths).recommend(dx12, executable: exe, bottle: bottle, settings: settings)
        try check(rec.backend == .d3dmetal && rec.automatic && rec.availabilityIssue != nil, "Missing required backend is diagnosed, not silently substituted")
        let ambiguous = ExecutableGraphicsAnalysis(architecture: .x64, apis: [.d3d11, .d3d12], imports: [], fingerprint: "mixed", limited: false, explanation: "Mixed")
        try check(!manager.recommend(ambiguous, executable: exe, bottle: bottle, settings: settings).automatic, "Mixed APIs do not guess")
        try check(!manager.recommend(dx12, executable: root.appending(path: "Steam.exe"), bottle: bottle, settings: settings).automatic, "Launcher is not mistaken for a game")
        var custom = settings; custom.environment["WINEDLLOVERRIDES"] = "d3d11=b"
        try check(!manager.recommend(dx12, executable: exe, bottle: bottle, settings: custom).automatic, "Custom graphics environment respected")

        try pe(imports: ["opengl32.dll"]).write(to: exe)
        settings.graphicsMode = .manual; settings.manualBackend = .none
        try await ProgramSettingsFiles.save(settings, for: exe, in: bottleDir)
        do { _ = try await manager.confirmWorking(exe, bottle: bottle, settings: settings); throw ProbeError("An application that had not been launched was confirmed") }
        catch is RuntimeInstallerError { }
        let running = ProgramGraphicsManager(paths: paths, activity: UpdateActivity(processCheck: { true }), availabilityCheck: { _, _, _ in nil })
        do { _ = try await running.prepareLaunch(exe, bottle: bottle); throw ProbeError("Changed shared DLL configuration while Wine was running") }
        catch is UpdateActivityError { }
        try check(try Data(contentsOf: sentinel) == Data("preserved game save".utf8), "Blocked transition preserved saves")
        do {
            let prepared = try await manager.prepareLaunch(exe, bottle: bottle)
            try check(prepared.bottle.settings.backend.backend == .none, "Explicit manual override wins over detected OpenGL")
            bottle = prepared.bottle
            do { _ = try activity.acquireMaintenance(); throw ProbeError("Launch lost its configuration lease") }
            catch is UpdateActivityError { }
            try await manager.recordLaunch(exe, bottle: bottle, choice: prepared.choice)
            withExtendedLifetime(prepared.lease) {}
        }
        let hasSnapshot = await BottleRuntimeManager(paths: paths, activity: activity).hasSnapshot(for: bottle)
        try check(hasSnapshot, "Backend transition produced a recovery snapshot")
        settings = try ProgramSettingsFiles.load(for: exe, in: bottleDir)
        settings.graphicsMode = .automatic
        settings = try await manager.confirmWorking(exe, bottle: bottle, settings: settings)
        let remembered = await manager.recommendation(for: exe, bottle: bottle, settings: settings)
        try check(remembered.remembered && remembered.backend == TranslationBackend.none, "User-confirmed choice is reused")
        var inheritConfirmation = settings; inheritConfirmation.graphicsMode = .bottle
        try check(manager.recommend(ExecutableGraphicsInspector.inspect(exe), executable: exe, bottle: bottle, settings: inheritConfirmation).remembered, "Bottle Auto did not reuse the confirmed application choice")
        var manual = settings; manual.graphicsMode = .manual; manual.manualBackend = .dxvk
        try check(manager.recommend(gl, executable: exe, bottle: bottle, settings: manual).backend == .dxvk, "Manual override takes priority over a remembered choice")
        var args = settings; args.arguments = "-different-renderer"
        let changedArguments = await manager.recommendation(for: exe, bottle: bottle, settings: args)
        try check(!changedArguments.remembered, "Changed launch arguments invalidate confirmation")
        try pe(imports: ["d3d11.dll"]).write(to: exe)
        let changedExecutable = await manager.recommendation(for: exe, bottle: bottle, settings: settings)
        try check(!changedExecutable.remembered, "Changed executable invalidates confirmation")
        try check(try ProgramSettingsFiles.load(for: exe, in: bottleDir).confirmedGraphics != nil, "Stale confirmation remains recoverable")
        settings.environment["WINEDLLOVERRIDES"] = "d3d11=b"
        try await ProgramSettingsFiles.save(settings, for: exe, in: bottleDir)
        try await manager.recordLaunch(exe, bottle: bottle, choice: nil, environment: settings.effectiveEnvironment())
        settings = try await manager.confirmWorking(exe, bottle: bottle, settings: settings)
        let customConfirmed = await manager.recommendation(for: exe, bottle: bottle, settings: settings)
        try check(customConfirmed.remembered, "A matching explicit working confirmation lost priority to inference")

        let profile = ProgramSettingsFiles.url(for: exe, in: bottleDir)
        let future = try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 99, "arguments": "keep this"], format: .xml, options: 0)
        try future.write(to: profile)
        do { try await ProgramSettingsFiles.save(ProgramSettings(), for: exe, in: bottleDir); throw ProbeError("Future profile overwritten") }
        catch is DecodingError { }
        try check(try Data(contentsOf: profile) == future, "Future application profile preserved")
        let sleeper = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appending(path: "wine64-prefix-probe")
        let owned = Process(), other = Process()
        let otherPrefix = root.appending(path: "OtherBottle")
        try FileManager.default.createDirectory(at: otherPrefix, withIntermediateDirectories: true)
        owned.executableURL = sleeper; other.executableURL = sleeper
        owned.environment = ["WINEPREFIX": bottleDir.path, "SCOTCH_TEST_PRIVATE": "never-log-environment"]
        other.environment = ["WINEPREFIX": otherPrefix.path]
        try owned.run(); try other.run()
        defer { if owned.isRunning { owned.terminate() }; if other.isRunning { other.terminate() } }
        try check(WineProcessInspector.hasWineProcesses, "Idle gate missed a Wine process")
        await WineProcessInspector.stopRemainingProcesses(in: bottleDir)
        try await Task.sleep(for: .milliseconds(100))
        try check(!owned.isRunning && other.isRunning, "Prefix-scoped stop touched another bottle or missed its own process")
        await WineProcessInspector.stopRemainingProcesses(in: otherPrefix)
        print("Passed: PE architecture, normal/delay/dependency imports, malformed files, fingerprints, conservative policy, manual/working priorities, configuration invalidation, missing runtimes, idle gates, atomic launch lease, snapshots and future profiles")
    }
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw ProbeError(message) }
    }
    static func put(_ value: UInt32, at offset: Int, data: inout Data, count: Int = 4) {
        for i in 0..<count { data[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }
    static func pe(imports: [String], x64: Bool = true, delayed: Bool = false) -> Data {
        var bytes = Data(count: 2048)
        bytes[0] = 0x4d; bytes[1] = 0x5a
        put(0x80, at: 60, data: &bytes); put(0x4550, at: 0x80, data: &bytes)
        put(x64 ? 0x8664 : 0x14c, at: 0x84, data: &bytes, count: 2)
        put(1, at: 0x86, data: &bytes, count: 2)
        let optional = 0x98, optionalSize = x64 ? 240 : 224
        put(UInt32(optionalSize), at: 0x94, data: &bytes, count: 2)
        put(x64 ? 0x20b : 0x10b, at: optional, data: &bytes, count: 2)
        put(0x200, at: optional + 60, data: &bytes)
        put(16, at: optional + (x64 ? 108 : 92), data: &bytes)
        let directories = optional + (x64 ? 112 : 96), table = optional + optionalSize
        put(0x600, at: table + 8, data: &bytes); put(0x1000, at: table + 12, data: &bytes)
        put(0x600, at: table + 16, data: &bytes); put(0x200, at: table + 20, data: &bytes)
        let stride = delayed ? 32 : 20, dir = directories + (delayed ? 13 : 1) * 8
        put(0x1100, at: dir, data: &bytes); put(UInt32((imports.count + 1) * stride), at: dir + 4, data: &bytes)
        for (i, name) in imports.enumerated() {
            let offset = 0x500 + i * 80
            if delayed { put(1, at: 0x300 + i * stride, data: &bytes) }
            put(UInt32(offset - 0x200 + 0x1000), at: 0x300 + i * stride + (delayed ? 4 : 12), data: &bytes)
            bytes.replaceSubrange(offset..<offset + name.utf8.count, with: name.utf8)
        }
        return bytes
    }
}
private struct ProbeError: LocalizedError { let errorDescription: String?; init(_ message: String) { errorDescription = message } }
