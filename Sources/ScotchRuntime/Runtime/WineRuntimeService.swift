import Foundation
import ScotchDomain
import ScotchInfrastructure

private enum RegistryValueType: String {
    case string = "REG_SZ"
    case dword = "REG_DWORD"
}

public actor WineRuntimeService: WineRuntimeServiceProtocol {
    private static let defaultKillTimeout: TimeInterval = 3

    private let paths: AppPaths
    private let processRunner: ProcessRunner
    private let fileSystem: LocalFileSystem
    private let logger: AppLogger
    private let logStore: LogStore
    private let envAssembler: EnvironmentAssembler

    private var latestLogByBottleID: [BottleID: URL] = [:]

    public init(
        paths: AppPaths,
        processRunner: ProcessRunner,
        fileSystem: LocalFileSystem,
        logger: AppLogger,
        logStore: LogStore,
        envAssembler: EnvironmentAssembler
    ) {
        self.paths = paths
        self.processRunner = processRunner
        self.fileSystem = fileSystem
        self.logger = logger
        self.logStore = logStore
        self.envAssembler = envAssembler
    }

    public func runProgram(
        at url: URL,
        arguments: [String],
        bottle: BottleSummary,
        extraEnvironment: [String: String]
    ) async throws {
        try await prepareBottleForLaunch(bottle)

        try await runWineBundle(
            arguments: ["start", "/unix", url.path(percentEncoded: false)] + arguments,
            bottle: bottle,
            extraEnvironment: extraEnvironment,
            displayName: url.lastPathComponent
        )
    }

    public func runSteam(in bottle: BottleSummary, arguments: [String] = []) async throws {
        guard let steamExecutable = steamExecutableURL(in: bottle) else {
            throw RuntimeInstallerError.installFailed("Steam executable not found in bottle")
        }
        try await runProgram(at: steamExecutable, arguments: arguments, bottle: bottle, extraEnvironment: [:])
    }

    public func runBatchFile(
        at url: URL,
        bottle: BottleSummary,
        extraEnvironment: [String: String]
    ) async throws {
        try await prepareBottleForLaunch(bottle)
        try await runWineBundle(
            arguments: ["cmd", "/c", url.path(percentEncoded: false)],
            bottle: bottle,
            extraEnvironment: extraEnvironment,
            displayName: url.lastPathComponent
        )
    }

    public func runGUITool(arguments: [String], bottle: BottleSummary) async throws {
        try await prepareBottleForLaunch(bottle)
        try await runWineBundle(
            arguments: arguments,
            bottle: bottle,
            extraEnvironment: [:],
            displayName: arguments.first ?? "wine"
        )
    }

    public func prepareBottleForLaunch(_ bottle: BottleSummary) async throws {
        try ensureRuntimeReady()
        try applyBackendDLLs(for: bottle)
        try writeDXVKConfigIfNeeded(for: bottle)
        await syncCompatibilityRegistry(for: bottle)
    }

    public func runWine(arguments: [String], bottle: BottleSummary?, environment: [String: String]) async throws -> String {
        let logDestination = try await logStore.createLogFile(bottleID: bottle?.id)
        defer { try? logDestination.fileHandle.close() }
        logDestination.fileHandle.writeLogHeader(appName: "Scotch", bundleIdentifier: paths.bundleIdentifier)

        var processEnvironment = environment
        if let bottle {
            processEnvironment = envAssembler.makeWineEnvironment(bottle: bottle, extra: environment)
            latestLogByBottleID[bottle.id] = logDestination.fileURL
            logDestination.fileHandle.writeBottleInfo(
                name: bottle.settings.info.name,
                path: bottle.directoryURL.path(percentEncoded: false),
                backend: bottle.settings.backend.backend.displayName
            )
        }

        let specification = ProcessSpecification(
            executableURL: paths.wineBinaryURL,
            arguments: arguments,
            environment: processEnvironment,
            displayName: "wine"
        )

        return try await processRunner.captureProcess(specification, outputFileHandle: logDestination.fileHandle)
    }

    public func runWineServer(arguments: [String], bottle: BottleSummary) async throws -> String {
        try await runWineServerInternal(arguments: arguments, bottle: bottle, timeout: nil)
    }

    private func runWineServerInternal(arguments: [String], bottle: BottleSummary, timeout: TimeInterval?) async throws -> String {
        let logDestination = try await logStore.createLogFile(bottleID: bottle.id)
        defer { try? logDestination.fileHandle.close() }
        latestLogByBottleID[bottle.id] = logDestination.fileURL

        let specification = ProcessSpecification(
            executableURL: paths.wineServerBinaryURL,
            arguments: arguments,
            environment: envAssembler.makeWineServerEnvironment(bottle: bottle),
            displayName: "wineserver",
            timeout: timeout
        )

        return try await processRunner.captureProcess(specification, outputFileHandle: logDestination.fileHandle)
    }

    public func syncCompatibilityState(for bottle: BottleSummary) async {
        do {
            try writeDXVKConfigIfNeeded(for: bottle)
        } catch {
            logger.warning("Failed to write DXVK config for \(bottle.settings.info.name): \(error.localizedDescription)")
        }
        await syncCompatibilityRegistry(for: bottle)
    }

    public func killBottle(_ bottle: BottleSummary, timeout: TimeInterval? = nil) async {
        do {
            _ = try await runWineServerInternal(
                arguments: ["-k"],
                bottle: bottle,
                timeout: timeout ?? Self.defaultKillTimeout
            )
        } catch {
            logger.warning("Failed to kill bottle \(bottle.settings.info.name): \(error.localizedDescription)")
        }
    }

    public func latestLogURL(for bottle: BottleSummary) async -> URL? {
        if let cached = latestLogByBottleID[bottle.id] {
            return cached
        }
        return await logStore.recentLogs(for: bottle.id, limit: 1).first
    }

    public func recentLogs(limit: Int) async -> [URL] {
        await logStore.recentLogs(limit: limit)
    }

    public func readLog(at url: URL, maxCharacters: Int) async -> String {
        await logStore.readLog(at: url, maxCharacters: maxCharacters)
    }

    public func makeShellEnvironment(for bottle: BottleSummary) async -> [String: String] {
        envAssembler.makeShellEnvironment(bottle: bottle)
    }

    public func generateRunCommand(
        at url: URL,
        arguments: [String],
        bottle: BottleSummary,
        extraEnvironment: [String: String]
    ) async -> String {
        let environment = envAssembler.makeWineEnvironment(bottle: bottle, extra: extraEnvironment)
        let envFile = writeLaunchEnvironmentFile(environment, bottle: bottle)
        var launchEnvironment = environment
        launchEnvironment["SCOTCH_LAUNCH_ENV"] = envFile.path(percentEncoded: false)

        var command = "/usr/bin/open -n -a \(paths.wineBundleURL.shellEscapedPath) --arch x86_64"
        command += " --env SCOTCH_LAUNCH_ENV=\(envFile.path(percentEncoded: false).shellQuoted)"
        for key in Self.launchEnvironmentPassthroughKeys {
            guard let value = launchEnvironment[key], key.isShellEnvironmentKey else { continue }
            command += " --env \(key)=\(value.shellQuoted)"
        }
        command += " --args start /unix \(url.shellEscapedPath)"

        if !arguments.isEmpty {
            let escapedArguments = arguments.map { $0.shellEscaped }.joined(separator: " ")
            command += " \(escapedArguments)"
        }

        if let commandLineToolURL = bundledCommandLineToolURL() {
            let prepare = "\(commandLineToolURL.shellEscapedPath) prepare-path \(bottle.directoryURL.shellEscapedPath)"
            command = "\(prepare) && \(command)"
        }
        return command
    }

    private func runWineBundle(
        arguments: [String],
        bottle: BottleSummary,
        extraEnvironment: [String: String],
        displayName: String
    ) async throws {
        let logDestination = try await logStore.createLogFile(bottleID: bottle.id)
        defer { try? logDestination.fileHandle.close() }
        latestLogByBottleID[bottle.id] = logDestination.fileURL
        logDestination.fileHandle.writeLogHeader(appName: "Scotch", bundleIdentifier: paths.bundleIdentifier)
        logDestination.fileHandle.writeBottleInfo(
            name: bottle.settings.info.name,
            path: bottle.directoryURL.path(percentEncoded: false),
            backend: bottle.settings.backend.backend.displayName
        )

        let specification = wineBundleSpecification(
            arguments: arguments,
            bottle: bottle,
            extraEnvironment: extraEnvironment,
            displayName: displayName,
            logURL: logDestination.fileURL
        )
        _ = try await processRunner.captureProcess(specification, outputFileHandle: logDestination.fileHandle)
    }

    private static let launchEnvironmentPassthroughKeys = [
        "WINEPREFIX", "WINE", "WINELOADER", "WINESERVER", "PATH",
        "WINEDLLOVERRIDES", "WINEESYNC", "WINEMSYNC", "WINEDEBUG", "GST_DEBUG",
        "DXVK_HUD", "DXVK_ASYNC", "DXVK_CONFIG_FILE", "DXVK_VENDOR_ID", "DXVK_DEVICE_ID",
        "GALLIUM_DRIVER", "MESA_LOADER_DRIVER_OVERRIDE", "LIBGL_ALWAYS_SOFTWARE",
        "SCOTCH_GPU_SPOOF_LIB", "SCOTCH_GPU_VENDOR_ID", "SCOTCH_GPU_DEVICE_ID",
        "SCOTCH_GPU_DEVICE_NAME", "SCOTCH_GPU_VRAM_MB", "SCOTCH_REAL_MOLTENVK_PATH",
        "CX_LIBVULKAN", "DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH",
        "MVK_CONFIG_RESUME_LOST_DEVICE", "MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE",
        "ROSETTA_ADVERTISE_AVX", "MTL_HUD_ENABLED", "METAL_CAPTURE_ENABLED",
        "D3DM_SUPPORT_DXR", "W_CACHE", "HOME", "TMPDIR", "USER", "LANG"
    ]

    private func wineBundleSpecification(
        arguments: [String],
        bottle: BottleSummary,
        extraEnvironment: [String: String],
        displayName: String,
        logURL: URL
    ) -> ProcessSpecification {
        let environment = envAssembler.makeWineEnvironment(bottle: bottle, extra: extraEnvironment)
        let envFile = writeLaunchEnvironmentFile(environment, bottle: bottle)
        var launchEnvironment = environment
        launchEnvironment["SCOTCH_LAUNCH_ENV"] = envFile.path(percentEncoded: false)

        var openArguments = [
            "-n",
            "-a",
            paths.wineBundleURL.path(percentEncoded: false),
            "--arch", "x86_64",
            "--stdout", logURL.path(percentEncoded: false),
            "--stderr", logURL.path(percentEncoded: false),
            "--env", "SCOTCH_LAUNCH_ENV=\(envFile.path(percentEncoded: false))"
        ]

        let merged = ProcessInfo.processInfo.environment.merging(launchEnvironment, uniquingKeysWith: { _, new in new })
        for key in Self.launchEnvironmentPassthroughKeys {
            guard let value = merged[key], key.isShellEnvironmentKey else { continue }
            openArguments.append("--env")
            openArguments.append("\(key)=\(value)")
        }

        openArguments.append("--args")
        openArguments.append(contentsOf: arguments)

        return ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: openArguments,
            environment: launchEnvironment,
            displayName: displayName
        )
    }

    private func writeLaunchEnvironmentFile(_ environment: [String: String], bottle: BottleSummary) -> URL {
        let directory = paths.launchEnvironmentDirectory
        if !fileSystem.fileExists(at: directory) {
            try? fileSystem.createDirectory(at: directory)
        }
        let url = directory.appending(path: "\(bottle.id.rawValue).env")
        let body = envAssembler.launchEnvironmentFileContents(environment)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func listProcesses(in bottle: BottleSummary) async throws -> [BottleProcessInfo] {
        let output = try await runWine(arguments: ["tasklist.exe", "/FO", "CSV", "/NH"], bottle: bottle, environment: [:])
        return parseTaskListOutput(output)
    }

    public func killProcess(pid: Int, in bottle: BottleSummary) async throws {
        _ = try await runWine(arguments: ["taskkill.exe", "/PID", "\(pid)", "/F"], bottle: bottle, environment: [:])
    }

    private func ensureRuntimeReady() throws {
        if !fileSystem.fileExists(at: paths.wineBinaryURL) {
            throw RuntimeInstallerError.installFailed("Wine binary missing at \(paths.wineBinaryURL.path(percentEncoded: false))")
        }
        if !fileSystem.fileExists(at: paths.wineBundleURL) {
            throw RuntimeInstallerError.installFailed("Wine.app bundle missing")
        }
    }

    private func bundledCommandLineToolURL() -> URL? {
        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }

        let candidates = [
            executableURL.deletingLastPathComponent().appending(path: "ScotchCmd"),
            executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Helpers/ScotchCmd"),
            URL(fileURLWithPath: "/Applications/Scotch.app/Contents/MacOS/ScotchCmd")
        ]

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }
    }

    private func steamExecutableURL(in bottle: BottleSummary) -> URL? {
        let candidates = [
            bottle.directoryURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe"),
            bottle.directoryURL.appending(path: "drive_c/Program Files/Steam/steam.exe"),
            bottle.directoryURL.appending(path: "drive_c/program files (x86)/Steam/steam.exe"),
            bottle.directoryURL.appending(path: "drive_c/program files/Steam/steam.exe")
        ]

        return candidates.first(where: { fileSystem.fileExists(at: $0) })
    }

    private func parseTaskListOutput(_ output: String) -> [BottleProcessInfo] {
        let lines = output
            .split(whereSeparator: \ .isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var result: [BottleProcessInfo] = []

        for line in lines {
            let columns = parseCSVLine(line)
            guard columns.count > 1 else { continue }

            let name = columns[0]
            let pidRaw = columns[1]
            guard let pid = Int(pidRaw) else { continue }
            result.append(BottleProcessInfo(pid: pid, processName: name))
        }

        return result.sorted { lhs, rhs in
            lhs.pid < rhs.pid
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for character in line {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == "," && !inQuotes {
                fields.append(current)
                current = ""
                continue
            }
            current.append(character)
        }

        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func applyBackendDLLs(for bottle: BottleSummary) throws {
        let driveWindows = bottle.directoryURL.appending(path: "drive_c/windows")
        let system32 = driveWindows.appending(path: "system32")
        let syswow64 = driveWindows.appending(path: "syswow64")

        try fileSystem.restoreOriginalDLLs(in: system32)
        try fileSystem.restoreOriginalDLLs(in: syswow64)

        switch bottle.settings.backend.backend {
        case .dxvk:
            try fileSystem.replaceDLLs(in: system32, from: paths.librariesDirectory.appending(path: "DXVK/x64"))
            try fileSystem.replaceDLLs(in: syswow64, from: paths.librariesDirectory.appending(path: "DXVK/x32"))
        case .dxmt:
            try fileSystem.replaceDLLs(in: system32, from: paths.librariesDirectory.appending(path: "DXMT/x64"))
            try fileSystem.replaceDLLs(in: syswow64, from: paths.librariesDirectory.appending(path: "DXMT/x32"))
        case .d3dmetal:
            try fileSystem.replaceDLLs(in: system32, from: paths.librariesDirectory.appending(path: "D3DMetal/x64"))
            let x32 = paths.librariesDirectory.appending(path: "D3DMetal/x32")
            if fileSystem.fileExists(at: x32) {
                try fileSystem.replaceDLLs(in: syswow64, from: x32, requireAtLeastOneDLL: false)
            }
        case .zink:
            try installZinkDLLs(system32: system32, syswow64: syswow64)
        case .none:
            break
        }

        if bottle.settings.backend.glZinkEnabled && bottle.settings.backend.backend != .zink {
            try installZinkDLLs(system32: system32, syswow64: syswow64)
        }
    }

    private func installZinkDLLs(system32: URL, syswow64: URL) throws {
        try fileSystem.replaceDLLs(in: system32, from: paths.librariesDirectory.appending(path: "Zink/x64"))
        let zinkX32 = paths.librariesDirectory.appending(path: "Zink/x32")
        if fileSystem.fileExists(at: zinkX32) {
            try fileSystem.replaceDLLs(in: syswow64, from: zinkX32, requireAtLeastOneDLL: false)
        }
    }

    private func writeDXVKConfigIfNeeded(for bottle: BottleSummary) throws {
        let configURL = bottle.directoryURL.appending(path: "dxvk.conf")
        guard bottle.settings.backend.backend == .dxvk,
              let identity = bottle.settings.resolvedGPUIdentity() else {
            if fileSystem.fileExists(at: configURL) {
                try fileSystem.removeItem(at: configURL)
            }
            return
        }

        let content = """
        dxgi.customVendorId = \(String(identity.vendorId, radix: 16))
        dxgi.customDeviceId = \(String(identity.deviceId, radix: 16))
        dxgi.customDeviceDesc = \(identity.description)
        dxgi.maxDeviceMemory = \(identity.vramMB)
        """
        try content.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func syncCompatibilityRegistry(for bottle: BottleSummary) async {
        let zinkActive = bottle.settings.backend.backend == .zink || bottle.settings.backend.glZinkEnabled
        let steamBuiltin = bottle.settings.backend.steamBuiltinOpenGL && zinkActive
        var failures: [String] = []

        if zinkActive {
            for key in ["opengl32", "libgallium_wgl", "libglapi"] {
                if let failure = await registryResult("set \(key) override", operation: {
                    try await addRegistryValue(
                        bottle: bottle,
                        key: #"HKCU\Software\Wine\DllOverrides"#,
                        name: key,
                        type: .string,
                        value: "native,builtin"
                    )
                }) {
                    failures.append(failure)
                }
            }
        } else {
            for key in ["opengl32", "libgallium_wgl", "libglapi"] {
                if let failure = await registryResult("delete \(key) override", operation: {
                    try await deleteRegistryValue(
                        bottle: bottle,
                        key: #"HKCU\Software\Wine\DllOverrides"#,
                        name: key
                    )
                }) {
                    failures.append(failure)
                }
            }
        }

        if steamBuiltin {
            if let failure = await registryResult("set Steam OpenGL override", operation: {
                try await addRegistryValue(
                    bottle: bottle,
                    key: #"HKCU\Software\Wine\AppDefaults\steam.exe\DllOverrides"#,
                    name: "opengl32",
                    type: .string,
                    value: "builtin"
                )
            }) {
                failures.append(failure)
            }
        } else {
            if let failure = await registryResult("delete Steam OpenGL override", operation: {
                try await deleteRegistryValue(
                    bottle: bottle,
                    key: #"HKCU\Software\Wine\AppDefaults\steam.exe\DllOverrides"#,
                    name: "opengl32"
                )
            }) {
                failures.append(failure)
            }
        }

        if let identity = bottle.settings.resolvedGPUIdentity() {
            if let failure = await registryResult("set GPU vendor ID", operation: {
                try await addRegistryValue(
                    bottle: bottle,
                    key: #"HKLM\Software\Wine\Direct3D"#,
                    name: "VideoPciVendorID",
                    type: .dword,
                    value: String(identity.vendorId)
                )
            }) {
                failures.append(failure)
            }
            if let failure = await registryResult("set GPU device ID", operation: {
                try await addRegistryValue(
                    bottle: bottle,
                    key: #"HKLM\Software\Wine\Direct3D"#,
                    name: "VideoPciDeviceID",
                    type: .dword,
                    value: String(identity.deviceId)
                )
            }) {
                failures.append(failure)
            }
            if let failure = await registryResult("set GPU memory size", operation: {
                try await addRegistryValue(
                    bottle: bottle,
                    key: #"HKLM\Software\Wine\Direct3D"#,
                    name: "VideoMemorySize",
                    type: .string,
                    value: String(identity.vramMB)
                )
            }) {
                failures.append(failure)
            }
        } else {
            for key in ["VideoPciVendorID", "VideoPciDeviceID", "VideoMemorySize"] {
                if let failure = await registryResult("delete \(key)", operation: {
                    try await deleteRegistryValue(
                        bottle: bottle,
                        key: #"HKLM\Software\Wine\Direct3D"#,
                        name: key
                    )
                }) {
                    failures.append(failure)
                }
            }
        }

        if !failures.isEmpty {
            logger.warning("Compatibility registry sync completed with warnings for \(bottle.settings.info.name): \(failures.joined(separator: "; "))")
        }
    }

    private func registryResult(
        _ description: String,
        operation: () async throws -> Void
    ) async -> String? {
        do {
            try await operation()
            return nil
        } catch {
            return "\(description): \(error.localizedDescription)"
        }
    }

    private func addRegistryValue(
        bottle: BottleSummary,
        key: String,
        name: String,
        type: RegistryValueType,
        value: String
    ) async throws {
        _ = try await runWineInternal(
            arguments: ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", value, "-f"],
            bottle: bottle,
            environment: [:]
        )
    }

    private func deleteRegistryValue(
        bottle: BottleSummary,
        key: String,
        name: String
    ) async throws {
        _ = try await runWineInternal(
            arguments: ["reg", "delete", key, "-v", name, "-f"],
            bottle: bottle,
            environment: [:]
        )
    }

    private func runWineInternal(
        arguments: [String],
        bottle: BottleSummary,
        environment: [String: String]
    ) async throws -> String {
        let specification = ProcessSpecification(
            executableURL: paths.wineBinaryURL,
            arguments: arguments,
            environment: envAssembler.makeWineEnvironment(bottle: bottle, extra: environment),
            displayName: "wine"
        )
        return try await processRunner.captureProcess(specification, outputFileHandle: nil)
    }
}
