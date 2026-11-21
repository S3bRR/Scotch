import Foundation
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

/// CI checks the real bundled extractor through Winetricks' final process
/// environment. An optional live mode creates only an isolated Windows 11 bottle.
@main struct BottleCreationProbe {
    static func main() async {
        do {
            if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--live" {
                try await live(libraries: URL(fileURLWithPath: CommandLine.arguments[2]))
            } else {
                try await environment()
            }
        } catch {
            say("Bottle creation check failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func environment() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "Scotch Winetricks Test \(UUID().uuidString)")
        var paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.BottleCreationProbe.\(UUID().uuidString)")
        paths.runtimeDirectoryOverride = root.appending(path: "Runtime with spaces")
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: paths.applicationSupportDirectory) }
        try fm.createDirectory(at: paths.librariesDirectory, withIntermediateDirectories: true)
        let bottle = BottleSummary(id: BottleID(), directoryURL: root.appending(path: "Windows 11 Bottle"), settings: BottleSettings(wine: BottleWineConfig(windowsVersion: .win11)), isAvailable: true)
        try fm.createDirectory(at: bottle.directoryURL, withIntermediateDirectories: true)
        // This runs the actual extractor through the process environment that
        // previously lost the resource directory when Wine merged its PATH.
        try Data("""
        #!/bin/bash
        set -eu
        resolved="$(command -v cabextract)"
        case "$resolved" in
          */Scotch_ScotchRuntime.bundle/cabextract) ;;
          *) echo 'Did not resolve the bundled extractor'; exit 1 ;;
        esac
        cabextract --version
        """.utf8).write(to: paths.winetricksScriptURL)
        let service = WinetricksService(paths: paths, fileSystem: LocalFileSystem(), logger: ProbeLogger())
        let output = try await service.run(command: "probe", in: bottle, mode: .headless)
        try check(output.contains("cabextract version"), "Bundled extractor did not execute")
        let runner = TerminalEnvironmentProbe(expectedWine: paths.forBottle(bottle).wineBinaryURL.path, expectedServer: paths.forBottle(bottle).wineServerBinaryURL.path)
        let terminal = WinetricksService(paths: paths, fileSystem: LocalFileSystem(), logger: ProbeLogger(), processRunner: runner)
        _ = try await terminal.run(command: "corefonts", in: bottle, mode: .terminal)
        say("Passed: Finder-style PATH resolves and executes bundled cabextract; Terminal retains the matched Wine/wineserver environment and quoted paths.")
    }

    static func live(libraries: URL) async throws {
        let fm = FileManager.default
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.BottleCreationLiveProbe.\(UUID().uuidString)")
        let logger = ProbeLogger(), store = PlistStore(), runner = DefaultProcessRunner()
        try fm.createDirectory(at: paths.applicationSupportDirectory, withIntermediateDirectories: true)
        try fm.copyItem(at: libraries, to: paths.librariesDirectory)
        // An older installed test fixture may contain development headers.
        let headers = paths.librariesDirectory.appending(path: "MetalEngine/Engine/include")
        if fm.fileExists(atPath: headers.path) { try fm.removeItem(at: headers) }
        let logs = LogStore(logsDirectory: paths.logsDirectory)
        let runtime = WineRuntimeService(paths: paths, processRunner: runner, fileSystem: LocalFileSystem(), logger: logger, logStore: logs, envAssembler: EnvironmentAssembler(paths: paths))
        let fonts = WinetricksService(paths: paths, fileSystem: LocalFileSystem(), logger: logger)
        let repository = BottleRepository(paths: paths, fileSystem: LocalFileSystem(), plistStore: store, runtimeService: runtime, winetricksService: fonts, logger: logger, processRunner: runner)
        var bottle: BottleSummary?
        do {
            var created = try await repository.prepareBottle(name: "Windows 11 core fonts test", windowsVersion: .win11, containerURL: paths.defaultBottlesDirectory)
            bottle = created
            created = try await repository.setupWineEnvironment(created, progress: nil)
            bottle = created
            created = try await repository.installBottleCoreFonts(created) { fraction in
                say("Bottle setup progress: \(Int(fraction * 100))%")
            }
            bottle = created
            try check(created.setupWarningMessage == nil, created.setupWarningMessage ?? "Unexpected setup warning")
            try check(created.isAvailable && !created.inFlight && created.setupProgress == 1, "Bottle was not finalized")
            try check(created.settings.backend.backend == .d3dmetal && created.settings.wine.windowsVersion == .win11, "Windows 11 / D3DMetal default lost")
            let directory = created.directoryURL.appending(path: "drive_c/windows/Fonts")
            let installed = Set(try fm.contentsOfDirectory(atPath: directory.path).map { $0.lowercased() })
            for font in ["andalemo.ttf", "arial.ttf", "comic.ttf", "cour.ttf", "georgia.ttf", "impact.ttf", "times.ttf", "trebuc.ttf", "verdana.ttf", "webdings.ttf"] {
                try check(installed.contains(font), "Core font missing: \(font)")
            }
            let listed = await repository.loadBottles()
            try check(listed.contains(where: { $0.id == created.id && $0.settings.backend.backend == .d3dmetal }), "Published bottle did not retain D3DMetal")
            let log = try String(contentsOf: created.directoryURL.appending(path: "winetricks.log"), encoding: .utf8)
            for verb in ["andale", "arial", "comicsans", "courier", "georgia", "impact", "times", "trebuchet", "verdana", "webdings"] {
                try check(log.split(separator: "\n").contains(Substring(verb)), "Font verb was not registered: \(verb)")
            }
            // Retry through the existing user's Winetricks action as well.
            _ = try await fonts.run(command: "corefonts", in: created, mode: .headless)
            await runtime.killBottle(created, timeout: 15)
            say("Passed: complete Windows 11 bottle creation, all ten core font families, Winetricks retry and default D3DMetal persistence.")
        } catch {
            if let bottle { await runtime.killBottle(bottle, timeout: 15) }
            say("Disposable diagnostics retained at \(paths.applicationSupportDirectory.path)")
            throw error
        }
        say("Disposable diagnostics retained at \(paths.applicationSupportDirectory.path)")
    }
}

private struct TerminalEnvironmentProbe: ProcessRunner {
    let expectedWine: String
    let expectedServer: String
    func captureProcess(_ spec: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        try check(spec.executableURL.path == "/usr/bin/osascript", "Expected only a captured Terminal command")
        let script = spec.arguments.joined(separator: " ")
        try check(script.contains(expectedWine) && script.contains(expectedServer), "Terminal did not retain matched Wine binaries")
        try check(script.contains("Scotch_ScotchRuntime.bundle") && !script.contains("WINE=wine "), "Terminal lost the extractor or selected engine")
        let compiled = FileManager.default.temporaryDirectory.appending(path: "ScotchTerminalSyntax-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: compiled) }
        _ = try await DefaultProcessRunner().captureProcess(ProcessSpecification(executableURL: URL(fileURLWithPath: "/usr/bin/osacompile"), arguments: ["-o", compiled.path, "-e", spec.arguments.last ?? ""], displayName: "Compile Terminal command", timeout: 30), outputFileHandle: nil)
        return ""
    }
    func streamProcess(_ spec: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> { throw ProbeError("Unexpected streaming process") }
}
private struct ProbeLogger: AppLogger {
    func info(_ message: String) { say(message) }
    func warning(_ message: String) { say("Warning: " + message) }
    func error(_ message: String) { say("Error: " + message) }
}
private struct ProbeError: LocalizedError { let errorDescription: String?; init(_ message: String) { errorDescription = message } }
private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws { if try !condition() { throw ProbeError(message) } }
private func say(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }
