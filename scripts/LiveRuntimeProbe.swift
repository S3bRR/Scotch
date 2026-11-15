import Foundation
import Darwin
import CryptoKit
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

/// Manual hardware/network check. Every prefix, server, and installer path uses
/// a unique test application ID; the user's Scotch data is never opened.
@main struct LiveRuntimeProbe {
    static func main() async {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.LiveProbe.\(UUID().uuidString)")
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let fm = FileManager.default
        let runner = BoundedRunner()
        let logger = ProbeLogger()
        let installer = RuntimeInstallerService(paths: paths, fileSystem: LocalFileSystem(), logger: logger, plistStore: PlistStore(), processRunner: runner)
        let runtime = WineRuntimeService(paths: paths, processRunner: runner, fileSystem: LocalFileSystem(), logger: logger, logStore: LogStore(logsDirectory: paths.logsDirectory), envAssembler: EnvironmentAssembler(paths: paths))
        var bottle = BottleSummary(id: BottleID(rawValue: "smoke"), directoryURL: paths.applicationSupportDirectory.appending(path: "Bottles/smoke"), settings: BottleSettings(), isAvailable: true)
        bottle.settings.backend.backend = .dxvk
        bottle.settings.backend.automatic = false
        var failure: Error?
        do {
            say("Downloading actual pinned runtime releases through URLSession…")
            let releases = try await installer.fetchLatestReleases()
            if CommandLine.arguments.count > 3 {
                let fixtures = URL(fileURLWithPath: CommandLine.arguments[3])
                let assets = [releases.wine, releases.dxvk, releases.dxmt, D3DMetalInstallation.toolkit, MetalEngineInstallation.asset]
                let names = [releases.wine.name, releases.dxvk.name, releases.dxmt.name, "game-porting-toolkit-3.0-3.tar.xz", "WineForge-0.6.0.3.dmg"]
                try fm.createDirectory(at: paths.cachesDirectory.appending(path: "RuntimePackages"), withIntermediateDirectories: true)
                for (asset, name) in zip(assets, names) {
                    let file = fixtures.appending(path: name)
                    if let hash = asset.sha256, (try? SHA256.hash(data: Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()) == hash {
                        try fm.copyItem(at: file, to: paths.cachesDirectory.appending(path: "RuntimePackages/" + hash))
                    }
                }
            }
            let archives = try await installer.downloadAll(releases: releases, progress: nil)
            let (manifest, overlays) = try await installer.installAll(from: archives)
            try check(overlays.allSatisfy(\.succeeded), "Actual setup returned warnings: \(overlays)")
            try check(manifest.d3dmetalVersion == D3DMetalInstallation.version, "D3DMetal version was not recorded")
            say("Passed: actual downloads, hashes, extraction, native bridge and engine startup")
            let coreHash = try Data(contentsOf: paths.wineBinaryURL)
            try fm.removeItem(at: paths.librariesDirectory.appending(path: "MetalEngine/EngineVersion"))
            let macDriver = paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so")
            let originalMacDriver = try Data(contentsOf: macDriver)
            try Data("invalid old Mac-driver overlay".utf8).write(to: macDriver)
            try check(await installer.needsGraphicsRepair(), "Missing engine marker must request repair")
            try await installer.repairGraphics()
            try check(!(await installer.needsGraphicsRepair()), "Repair remains advertised after success")
            try check(try Data(contentsOf: paths.wineBinaryURL) == coreHash, "Repair modified the Zink/core engine")
            try check(try Data(contentsOf: macDriver) == originalMacDriver, "Repair did not restore the stock Mac driver")
            say("Passed: targeted repair preserves core Wine and clears the repair state")
            try fm.createDirectory(at: bottle.directoryURL, withIntermediateDirectories: true)
            try await PlistStore().write(bottle.settings, to: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
            say("Initializing isolated prefix with the normal Wine 11.16 engine…")
            _ = try await runtime.runWine(arguments: ["wineboot", "--init"], bottle: bottle,
                environment: [:])
            await runtime.killBottle(bottle, timeout: 10)
            let save = bottle.directoryURL.appending(path: "drive_c/ScotchSmoke/save.dat")
            try fm.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("preserved save".utf8).write(to: save)
            let manager = BottleRuntimeManager(paths: paths)
            let probes = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent()
            for backend in [TranslationBackend.dxvk, .dxmt, .d3dmetal, .zink] {
                await runtime.killBottle(bottle, timeout: 10)
                var settings = bottle.settings
                settings.backend.backend = backend
                try await manager.switchBackend(for: bottle, settings: settings)
                bottle.settings = settings
                try await runtime.prepareBottleForLaunch(bottle)
                for (architecture, directory) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
                    let registered = bottle.directoryURL.appending(path: "drive_c/windows/\(directory)/winemetal.dll")
                    let original = paths.librariesDirectory.appending(path: "DXMT/\(architecture)/winemetal.dll")
                    try check(try Data(contentsOf: registered) == Data(contentsOf: original), "Fresh prefix is missing the matched winemetal builtin")
                }
                say("Rendering through the installed \(backend.displayName) backend…")
                if backend == .zink {
                    for name in ["ZinkSmoke.exe", "ZinkSmoke32.exe"] {
                        let result = try await runtime.runWine(arguments: [probes.appending(path: name).path], bottle: bottle, environment: [:])
                        try check(result.contains("OpenGL 4.5 DSA, compute, RGB32 fetch and textureSize=21500") && result.contains("OpenGL transform feedback=3,5,7,9"), "Zink shader checks did not complete: \(result)")
                        say("Passed: \(name), actual OpenGL 4.5+ shader execution and GPU readback")
                    }
                } else {
                    let names = backend == .d3dmetal ? ["D3DMetalSmoke.exe"] : (backend == .dxvk
                        ? ["D3DMetalSmoke.exe", "D3DMetalSmoke32.exe", "D3DMetalSmoke32.exe", "D3DMetalSmoke32.exe"]
                        : ["D3DMetalSmoke.exe", "D3DMetalSmoke32.exe"])
                    for name in names {
                        let arguments = [probes.appending(path: name).path] + (backend == .d3dmetal ? [] : ["--d3d11"])
                        let result = try await runtime.runWine(arguments: arguments, bottle: bottle, environment: ["DYLD_PRINT_LIBRARIES": "1"])
                        try check(result.contains("D3D11 readback="), "Missing D3D11 GPU readback")
                        let log = try await logText(runtime, bottle: bottle)
                        if backend == .d3dmetal {
                            try check(result.contains("D3D12 readback=") && log.contains("external/D3DMetal.framework/Versions/A/D3DMetal") && log.contains("external/libd3dshared.dylib"), "Actual D3DMetal D3D12 rendering was not used")
                        } else if backend == .dxmt {
                            try check(log.contains("DXMT/x86_64-unix/winemetal.so"), "Actual DXMT bridge was not loaded")
                        } else {
                            try check(result.contains("DXVK: v1.10.3"), "Actual DXVK was not selected")
                            // AppKit can load CGL independently of the renderer.
                            // Verify WineD3D's actual selected adapter backend.
                            try check(result.contains("Using the Vulkan renderer."), "DXGI adapter enumeration did not select Vulkan")
                        }
                        if backend != .dxvk { try check(!log.contains("/wined3d.dll"), "WineD3D silently replaced the selected renderer") }
                        say("Passed: \(backend.displayName), \(name), real GPU readback")
                    }
                }
                await runtime.killBottle(bottle, timeout: 10)
                let guiProbe = backend == .zink ? "ZinkSmoke.exe" : "D3DMetalSmoke.exe"
                try await runtime.runGUITool(arguments: [probes.appending(path: guiProbe).path] + (backend == .dxvk || backend == .dxmt ? ["--d3d11"] : []), bottle: bottle)
                let deadline = Date().addingTimeInterval(90)
                let expected = backend == .zink ? "OpenGL transform feedback=3,5,7,9" : "D3D11 Present HRESULT=0x00000000"
                var guiLog = ""
                repeat {
                    try await Task.sleep(for: .milliseconds(250))
                    guiLog = try await logText(runtime, bottle: bottle)
                } while !guiLog.contains(expected) && Date() < deadline
                try check(guiLog.contains(expected), "Wine.app launch failed for \(backend.displayName): \(guiLog)")
                say("Passed: Wine.app GUI launch and GPU rendering, \(backend.displayName)")
                try check(try String(contentsOf: save, encoding: .utf8) == "preserved save", "A backend switch changed saved data")
            }
            // Exercise the real launch-time Auto path, rather than applying
            // the expected backend directly in the test.
            for (name, expectedBackend, expectedOutput) in [("ZinkSmoke.exe", TranslationBackend.zink, "OpenGL transform feedback=3,5,7,9"), ("D3D12AutoSmoke.exe", .d3dmetal, "D3D12 readback=")] {
                await runtime.killBottle(bottle, timeout: 10)
                var reset = bottle.settings; reset.backend.backend = .dxvk; reset.backend.glZinkEnabled = false; reset.backend.automatic = true
                try await manager.switchBackend(for: bottle, settings: reset); bottle.settings = reset
                let executable = probes.appending(path: name)
                let program = ProgramSettings()
                try await ProgramSettingsFiles.save(program, for: executable, in: bottle.directoryURL)
                try await runtime.runProgram(at: executable, arguments: [], bottle: bottle, extraEnvironment: [:])
                bottle.settings = try await PlistStore().read(BottleSettings.self, from: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
                try check(bottle.settings.backend.backend == expectedBackend, "Auto did not select the detected API's backend")
                let deadline = Date().addingTimeInterval(90)
                var text = ""
                repeat {
                    try await Task.sleep(for: .milliseconds(250))
                    text = try await logText(runtime, bottle: bottle)
                } while !text.contains(expectedOutput) && Date() < deadline
                try check(text.contains(expectedOutput), "Auto-selected backend did not perform real GPU rendering")
                let savedProgram = try ProgramSettingsFiles.load(for: executable, in: bottle.directoryURL)
                try check(bottle.settings.backend.automatic && savedProgram.graphicsMode == .bottle, "Bottle Auto was not inherited by the default program profile")
                try check(savedProgram.lastGraphicsLaunch?.backend == expectedBackend && savedProgram.confirmedGraphics == nil, "Auto marked an unconfirmed launch as working")
                say("Passed: automatic API detection, protected selection, actual GPU rendering and launch recording, \(name)")
            }
            // Zink's additive mode must also work with each Direct3D backend.
            for backend in [TranslationBackend.dxvk, .dxmt, .d3dmetal] {
                await runtime.killBottle(bottle, timeout: 10)
                var settings = bottle.settings; settings.backend.backend = backend; settings.backend.glZinkEnabled = true
                try await manager.switchBackend(for: bottle, settings: settings); bottle.settings = settings
                try await runtime.prepareBottleForLaunch(bottle)
                let names = backend == .d3dmetal ? ["CombinedSmoke.exe"] : ["CombinedSmoke.exe", "CombinedSmoke32.exe"]
                for name in names {
                    let result = try await runtime.runWine(arguments: [probes.appending(path: name).path], bottle: bottle, environment: [:])
                    try check(result.contains("D3D11 Present HRESULT=0x00000000") && result.contains("OpenGL transform feedback=3,5,7,9"), "Combined graphics failed with \(backend.displayName)")
                    say("Passed: Direct3D and Zink in the same process, \(backend.displayName), \(name)")
                }

            }
            await runtime.killBottle(bottle, timeout: 10)
            let restored = try await manager.restore(for: bottle)
            try check(try String(contentsOf: save, encoding: .utf8) == "preserved save", "Recovery snapshot lost the original save")
            bottle = restored
            // Simulate an older app's already-selected Metal bottle with no
            // engine marker. Its first launch must create a recovery snapshot.
            bottle.settings.backend.backend = .dxmt
            try await PlistStore().write(bottle.settings, to: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
            try? fm.removeItem(at: bottle.directoryURL.appending(path: ".ScotchWineEngine"))
            try await runtime.prepareBottleForLaunch(bottle)
            try check(await manager.hasSnapshot(for: bottle), "Legacy engine adoption has no recovery snapshot")
            await runtime.killBottle(bottle, timeout: 10)
            say("Passed: installed backends, additive Zink, legacy engine adoption, and recoverable prefix/save preservation")

        } catch { failure = error }
        // Stop only this disposable prefix, using each of its own matching servers.
        for metal in [false, true] {
            var selected = paths; selected.usesMetalEngine = metal
            _ = try? await runner.captureProcess(ProcessSpecification(executableURL: selected.wineServerBinaryURL, arguments: ["-k"], environment: ["WINEPREFIX": bottle.directoryURL.path], displayName: "Stop disposable server", timeout: 10), outputFileHandle: nil)
        }
        try? fm.createDirectory(at: output, withIntermediateDirectories: true)
        if fm.fileExists(atPath: paths.logsDirectory.path) { try? fm.copyItem(at: paths.logsDirectory, to: output.appending(path: "Logs-\(UUID().uuidString)")) }
        try? fm.removeItem(at: paths.applicationSupportDirectory)
        try? fm.removeItem(at: paths.cachesDirectory)
        if let failure { say("Live runtime check failed: \(failure.localizedDescription)"); exit(1) }
    }
}
private func logText(_ runtime: WineRuntimeService, bottle: BottleSummary) async throws -> String {
    guard let log = await runtime.latestLogURL(for: bottle) else { throw ProbeError(message: "No backend log") }
    return try String(contentsOf: log, encoding: .utf8)
}
private struct BoundedRunner: ProcessRunner {
    func captureProcess(_ spec: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        let bounded = ProcessSpecification(executableURL: spec.executableURL, arguments: spec.arguments, currentDirectoryURL: spec.currentDirectoryURL, environment: spec.environment, displayName: spec.displayName, timeout: spec.timeout ?? 90)
        return try await DefaultProcessRunner().captureProcess(bounded, outputFileHandle: outputFileHandle)
    }
    func streamProcess(_ spec: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        try DefaultProcessRunner().streamProcess(spec, outputFileHandle: outputFileHandle)
    }
}
private struct ProbeLogger: AppLogger {
    func info(_ message: String) { say(message) }
    func warning(_ message: String) { say("Warning: " + message) }
    func error(_ message: String) { say("Error: " + message) }
}
private struct ProbeError: LocalizedError { let message: String; var errorDescription: String? { message } }
private func check(_ passed: Bool, _ message: String) throws { if !passed { throw ProbeError(message: message) } }
private func say(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
