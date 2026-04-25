import Foundation
import AppKit
import ScotchDomain
import ScotchInfrastructure

@MainActor
public final class BottleDetailViewModel: ObservableObject {
    @Published public var bottle: BottleSummary
    @Published public var programs: [ProgramRecord] = []
    @Published public var isLaunching = false
    @Published public var steamInstalled: Bool = false
    @Published public var isInstallingSteam: Bool = false
    @Published public var steamInstallProgress: Double = 0
    @Published public var statusMessage: String?

    private let container: ScotchContainer
    private var lastSavedSettings: BottleSettings
    private let currentVersionRegistryKey = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
    private let macDriverRegistryKey = #"HKCU\Software\Wine\Mac Driver"#
    private let desktopRegistryKey = #"HKCU\Control Panel\Desktop"#
    private let directInputRegistryKey = #"HKCU\Software\Wine\DirectInput"#
    private let controlPanelMouseRegistryKey = #"HKCU\Control Panel\Mouse"#

    public init(container: ScotchContainer, bottle: BottleSummary) {
        self.container = container
        self.bottle = bottle
        self.lastSavedSettings = bottle.settings
    }

    public func adoptBottle(_ newBottle: BottleSummary) {
        bottle = newBottle
        lastSavedSettings = newBottle.settings
    }

    public func refresh() async {
        programs = await container.bottleRepository.refreshPrograms(for: bottle.id)
        refreshSteamInstalled()
    }

    public func refreshSteamInstalled() {
        steamInstalled = Self.steamExecutableURL(for: bottle) != nil
    }

    private static func steamExecutableURL(for bottle: BottleSummary) -> URL? {
        let driveC = bottle.directoryURL.appending(path: "drive_c")
        let candidates = [
            "Program Files (x86)/Steam/steam.exe",
            "Program Files/Steam/steam.exe"
        ]
        for relative in candidates {
            let url = driveC.appending(path: relative)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }
        return nil
    }

    public func installSteam() async {
        guard !isInstallingSteam else { return }
        guard !steamInstalled else { return }

        isInstallingSteam = true
        steamInstallProgress = 0
        statusMessage = "Downloading Steam installer…"
        defer { isInstallingSteam = false }

        let downloadsDir = FileManager.default.temporaryDirectory.appending(path: "ScotchSteamInstall/\(bottle.id.rawValue)")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        let setupURL = downloadsDir.appending(path: "SteamSetup.exe")

        guard let remoteURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe") else {
            statusMessage = "Invalid Steam installer URL."
            return
        }

        do {
            if FileManager.default.fileExists(atPath: setupURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: setupURL)
            }
            let tempFile: URL
            do {
                tempFile = try await container.networkClient.download(from: NetworkRequest(url: remoteURL))
            } catch let NetworkClientError.nonSuccessStatus(_, status) {
                statusMessage = "Download failed: HTTP \(status)."
                return
            } catch {
                statusMessage = "Download failed: \(error.localizedDescription)"
                return
            }
            try FileManager.default.moveItem(at: tempFile, to: setupURL)
            steamInstallProgress = 0.25

            statusMessage = "Running Steam installer… follow the prompts in the Wine window."
            try await container.runtimeService.runProgram(
                at: setupURL,
                arguments: [],
                bottle: bottle,
                extraEnvironment: [:]
            )
            steamInstallProgress = 0.5

            let deadline = Date().addingTimeInterval(15 * 60)
            while Date() < deadline {
                if let steamURL = Self.steamExecutableURL(for: bottle) {
                    steamInstallProgress = 1.0
                    steamInstalled = true
                    _ = steamURL
                    break
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            if steamInstalled, let steamURL = Self.steamExecutableURL(for: bottle) {
                try? FileManager.default.removeItem(at: setupURL)
                try? FileManager.default.removeItem(at: downloadsDir)

                let path = steamURL.path(percentEncoded: false)
                if !bottle.settings.info.pins.contains(where: { $0.executablePath.caseInsensitiveCompare(path) == .orderedSame }) {
                    var settings = bottle.settings
                    settings.info.pins.append(
                        PinnedProgram(name: "Steam", executablePath: path, removable: true)
                    )
                    await saveSettings(settings)
                }
                await refresh()
                statusMessage = "Steam installed and pinned."
            } else if steamInstalled {
                statusMessage = "Steam installed successfully."
            } else {
                statusMessage = "Steam installer did not finish. You can retry from the Install Steam button."
            }
        } catch {
            statusMessage = "Steam install failed: \(error.localizedDescription)"
        }
    }

    public func saveSettings(_ settings: BottleSettings) async {
        let previousSettings = lastSavedSettings
        var stagedBottle = bottle
        stagedBottle.settings = settings

        do {
            if previousSettings.wine.windowsVersion != settings.wine.windowsVersion {
                _ = try await container.runtimeService.runWine(
                    arguments: ["winecfg", "-v", settings.wine.windowsVersion.rawValue],
                    bottle: stagedBottle,
                    environment: [:]
                )
            }

            try await container.bottleRepository.saveSettings(settings, for: bottle.id)
            bottle.settings = settings
            lastSavedSettings = settings

            if compatibilityInputsChanged(from: previousSettings, to: settings) {
                await container.runtimeService.syncCompatibilityState(for: stagedBottle)
            }
        } catch {
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    public func pinExecutable(at url: URL) async {
        let path = url.path(percentEncoded: false)
        guard !bottle.settings.info.pins.contains(where: { $0.executablePath == path }) else {
            statusMessage = "\(url.deletingPathExtension().lastPathComponent) is already pinned."
            return
        }

        var settings = bottle.settings
        settings.info.pins.append(
            PinnedProgram(
                name: url.deletingPathExtension().lastPathComponent,
                executablePath: path,
                removable: true
            )
        )
        await saveSettings(settings)
        await refresh()
        statusMessage = "Pinned \(url.lastPathComponent)."
    }

    public func unpin(_ program: ProgramRecord) async {
        let path = program.executableURL.path(percentEncoded: false)
        var settings = bottle.settings
        settings.info.pins.removeAll { $0.executablePath == path }
        await saveSettings(settings)
        await refresh()
    }

    public func renamePin(_ program: ProgramRecord, to newName: String) async {
        let path = program.executableURL.path(percentEncoded: false)
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var settings = bottle.settings
        if let index = settings.info.pins.firstIndex(where: { $0.executablePath == path }) {
            settings.info.pins[index].name = trimmed
        } else {
            settings.info.pins.append(
                PinnedProgram(name: trimmed, executablePath: path, removable: true)
            )
        }
        await saveSettings(settings)
        await refresh()
    }

    public func runProgram(_ program: ProgramRecord, arguments: [String] = [], environment: [String: String] = [:]) async {
        isLaunching = true
        defer { isLaunching = false }

        do {
            let programArguments = program.settings.parsedArguments()
            let mergedEnvironment = program.settings.effectiveEnvironment(extra: environment)
            try await container.runtimeService.runProgram(
                at: program.executableURL,
                arguments: programArguments + arguments,
                bottle: bottle,
                extraEnvironment: mergedEnvironment
            )
            statusMessage = "Launched \(program.displayName)."
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
        }
    }

    public func runProgramInTerminal(_ program: ProgramRecord) async {
        do {
            try await container.runtimeService.prepareBottleForLaunch(bottle)
        } catch {
            statusMessage = "Failed to prepare bottle: \(error.localizedDescription)"
            return
        }

        let command = await container.runtimeService.generateRunCommand(
            at: program.executableURL,
            arguments: program.settings.parsedArguments(),
            bottle: bottle,
            extraEnvironment: program.settings.effectiveEnvironment()
        )
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            statusMessage = "Failed to create terminal script."
            return
        }
        appleScript.executeAndReturnError(&error)

        if let error, let description = error["NSAppleScriptErrorMessage"] as? String {
            statusMessage = "Failed to run in Terminal: \(description)"
        } else {
            statusMessage = "Launched \(program.displayName) in Terminal."
        }
    }

    public func openBottleTerminal() async {
        let environment = await container.runtimeService.makeShellEnvironment(for: bottle)
        let command = makeShellEnvironmentCommand(from: environment)
        let escapedCommand = escapeAppleScriptString(command)

        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            statusMessage = "Failed to create terminal script."
            return
        }
        appleScript.executeAndReturnError(&error)

        if let error, let description = error["NSAppleScriptErrorMessage"] as? String {
            statusMessage = "Failed to open bottle shell: \(description)"
        } else {
            statusMessage = "Opened shell for \(bottle.settings.info.name)."
        }
    }

    public func runSteam(arguments: [String] = []) async {
        isLaunching = true
        defer { isLaunching = false }

        do {
            try await container.runtimeService.runSteam(in: bottle, arguments: arguments)
            statusMessage = "Steam started."
        } catch {
            statusMessage = "Steam launch failed: \(error.localizedDescription)"
        }
    }

    public func runFileURL(_ url: URL) async {
        isLaunching = true
        defer { isLaunching = false }

        do {
            if url.pathExtension.lowercased() == "bat" {
                try await container.runtimeService.runBatchFile(at: url, bottle: bottle, extraEnvironment: [:])
            } else {
                try await container.runtimeService.runProgram(at: url, arguments: [], bottle: bottle, extraEnvironment: [:])
            }
            statusMessage = "Started \(url.lastPathComponent)."
            await refresh()
        } catch {
            statusMessage = "Run failed: \(error.localizedDescription)"
        }
    }

    public func openBottleInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([bottle.directoryURL])
    }

    public func openCDrive() {
        NSWorkspace.shared.open(bottle.directoryURL.appending(path: "drive_c"))
    }

    public func openRecentLog() async {
        guard let logURL = await container.runtimeService.latestLogURL(for: bottle) else {
            statusMessage = "No log file found for this bottle yet."
            return
        }
        NSWorkspace.shared.open(logURL)
    }

    public func createShortcut(for program: ProgramRecord, destination: URL) async {
        do {
            let launchCommand = await container.runtimeService.generateRunCommand(
                at: program.executableURL,
                arguments: program.settings.parsedArguments(),
                bottle: bottle,
                extraEnvironment: program.settings.effectiveEnvironment()
            )
            try await container.shortcutService.createShortcut(
                for: program,
                in: bottle,
                destinationAppURL: destination,
                launchCommand: launchCommand
            )
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            statusMessage = "Shortcut created for \(program.displayName)."
        } catch {
            statusMessage = "Failed to create shortcut: \(error.localizedDescription)"
        }
    }

    public func saveProgramSettings(_ settings: ProgramSettings, for program: ProgramRecord) async {
        let executablePath = program.executableURL.path(percentEncoded: false)
        do {
            try await container.bottleRepository.saveProgramSettings(settings, forProgramAt: executablePath, bottleID: bottle.id)
            await refresh()
            statusMessage = "Saved settings for \(program.displayName)."
        } catch {
            statusMessage = "Failed to save program settings: \(error.localizedDescription)"
        }
    }

    public func addProgramToBlocklist(_ program: ProgramRecord) async {
        let blockedPath = program.executableURL.path(percentEncoded: false)
        var settings = bottle.settings

        guard !settings.info.blocklist.contains(where: { $0.caseInsensitiveCompare(blockedPath) == .orderedSame }) else {
            return
        }

        settings.info.blocklist.append(blockedPath)
        settings.info.pins.removeAll { $0.executablePath.caseInsensitiveCompare(blockedPath) == .orderedSame }
        await saveSettings(settings)
        await refresh()
        statusMessage = "Added \(program.displayName) to blocklist."
    }

    public func removeBlockedPath(_ blockedPath: String) async {
        var settings = bottle.settings
        let before = settings.info.blocklist.count
        settings.info.blocklist.removeAll { $0.caseInsensitiveCompare(blockedPath) == .orderedSame }
        guard settings.info.blocklist.count != before else { return }

        await saveSettings(settings)
        await refresh()
        statusMessage = "Removed item from blocklist."
    }

    public func fetchAdvancedConfig() async -> BottleAdvancedConfigSnapshot {
        async let build = queryRegistryValue(key: currentVersionRegistryKey, name: "CurrentBuild", typeToken: "REG_SZ")
        async let retina = queryRegistryValue(key: macDriverRegistryKey, name: "RetinaMode", typeToken: "REG_SZ")
        async let dpi = queryRegistryValue(key: desktopRegistryKey, name: "LogPixels", typeToken: "REG_DWORD")
        async let mouseWarp = queryRegistryValue(key: directInputRegistryKey, name: "MouseWarpOverride", typeToken: "REG_SZ")

        let buildRaw = (try? await build) ?? nil
        let retinaRaw = (try? await retina) ?? nil
        let dpiRaw = (try? await dpi) ?? nil
        let mouseWarpRaw = (try? await mouseWarp) ?? nil

        let buildVersion = Int(buildRaw ?? "") ?? 0
        let retinaMode = (retinaRaw?.lowercased() ?? "n") == "y"
        let dpiValue: Int
        if let dpiRaw {
            let normalized = dpiRaw.replacingOccurrences(of: "0x", with: "")
            dpiValue = Int(normalized, radix: 16) ?? 96
        } else {
            dpiValue = 96
        }
        let mouseWarpValue = mouseWarpRaw?.lowercased()
        let mouseFixEnabled = (mouseWarpValue == "force" || mouseWarpValue == "disable")

        return BottleAdvancedConfigSnapshot(
            buildVersion: buildVersion,
            retinaMode: retinaMode,
            dpi: dpiValue,
            mouseFixEnabled: mouseFixEnabled
        )
    }

    public func setBuildVersion(_ value: Int) async {
        do {
            _ = try await container.runtimeService.runWine(
                arguments: ["reg", "add", currentVersionRegistryKey, "-v", "CurrentBuild", "-t", "REG_SZ", "-d", "\(value)", "-f"],
                bottle: bottle,
                environment: [:]
            )
            _ = try await container.runtimeService.runWine(
                arguments: ["reg", "add", currentVersionRegistryKey, "-v", "CurrentBuildNumber", "-t", "REG_SZ", "-d", "\(value)", "-f"],
                bottle: bottle,
                environment: [:]
            )
            statusMessage = "Build version updated."
        } catch {
            statusMessage = "Failed to update build version: \(error.localizedDescription)"
        }
    }

    public func setRetinaMode(_ enabled: Bool) async {
        do {
            _ = try await container.runtimeService.runWine(
                arguments: ["reg", "add", macDriverRegistryKey, "-v", "RetinaMode", "-t", "REG_SZ", "-d", enabled ? "y" : "n", "-f"],
                bottle: bottle,
                environment: [:]
            )
            statusMessage = "Retina mode updated."
        } catch {
            statusMessage = "Failed to update Retina mode: \(error.localizedDescription)"
        }
    }

    public func setDPI(_ dpi: Int) async {
        do {
            _ = try await container.runtimeService.runWine(
                arguments: ["reg", "add", desktopRegistryKey, "-v", "LogPixels", "-t", "REG_DWORD", "-d", "\(dpi)", "-f"],
                bottle: bottle,
                environment: [:]
            )
            statusMessage = "DPI updated."
        } catch {
            statusMessage = "Failed to update DPI: \(error.localizedDescription)"
        }
    }

    public func setMouseFix(_ enabled: Bool) async {
        // Mouse acceleration is always off — user preference is "never want mouse accel."
        // These values stay set whether the Mouse Fix toggle is on or off.
        let alwaysOff: [(key: String, name: String, value: String)] = [
            (controlPanelMouseRegistryKey, "MouseSpeed",      "0"),
            (controlPanelMouseRegistryKey, "MouseThreshold1", "0"),
            (controlPanelMouseRegistryKey, "MouseThreshold2", "0")
        ]
        // Fix-specific overrides: applied on enable, removed on disable.
        let fixSpecific: [(key: String, name: String, value: String)] = [
            (directInputRegistryKey,       "MouseWarpOverride",   "force"),
            (macDriverRegistryKey,         "UsePreciseScrolling", "n"),
            (controlPanelMouseRegistryKey, "MouseSensitivity",    "10")
        ]

        do {
            for entry in alwaysOff {
                _ = try await container.runtimeService.runWine(
                    arguments: ["reg", "add", entry.key, "-v", entry.name,
                                "-t", "REG_SZ", "-d", entry.value, "-f"],
                    bottle: bottle,
                    environment: [:]
                )
            }

            if enabled {
                for entry in fixSpecific {
                    _ = try await container.runtimeService.runWine(
                        arguments: ["reg", "add", entry.key, "-v", entry.name,
                                    "-t", "REG_SZ", "-d", entry.value, "-f"],
                        bottle: bottle,
                        environment: [:]
                    )
                }
                statusMessage = "Mouse fix enabled."
            } else {
                for entry in fixSpecific {
                    _ = try? await container.runtimeService.runWine(
                        arguments: ["reg", "delete", entry.key, "-v", entry.name, "-f"],
                        bottle: bottle,
                        environment: [:]
                    )
                }
                statusMessage = "Mouse fix disabled. Acceleration remains off."
            }
        } catch {
            statusMessage = "Failed to update mouse fix: \(error.localizedDescription)"
        }
    }

    public func runControlPanel() async {
        do {
            _ = try await container.runtimeService.runWine(arguments: ["control"], bottle: bottle, environment: [:])
            statusMessage = "Control Panel launched."
        } catch {
            statusMessage = "Failed to launch Control Panel: \(error.localizedDescription)"
        }
    }

    public func runRegedit() async {
        do {
            _ = try await container.runtimeService.runWine(arguments: ["regedit"], bottle: bottle, environment: [:])
            statusMessage = "Regedit launched."
        } catch {
            statusMessage = "Failed to launch Regedit: \(error.localizedDescription)"
        }
    }

    public func runWineCfg() async {
        do {
            _ = try await container.runtimeService.runWine(arguments: ["winecfg"], bottle: bottle, environment: [:])
            statusMessage = "Winecfg launched."
        } catch {
            statusMessage = "Failed to launch Winecfg: \(error.localizedDescription)"
        }
    }

    private func queryRegistryValue(key: String, name: String, typeToken: String) async throws -> String? {
        let output = try await container.runtimeService.runWine(
            arguments: ["reg", "query", key, "-v", name],
            bottle: bottle,
            environment: [:]
        )
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let line = lines.first(where: { $0.contains(typeToken) }) else {
            return nil
        }

        let columns = line
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return columns.last
    }

    private func compatibilityInputsChanged(from old: BottleSettings, to new: BottleSettings) -> Bool {
        old.backend != new.backend || old.gpu != new.gpu
    }

    private func makeShellEnvironmentCommand(from environment: [String: String]) -> String {
        var lines: [String] = []

        if let path = environment["PATH"] {
            lines.append("export PATH=\(shellQuoted(path))")
        }
        if let wine = environment["WINE"] {
            lines.append("export WINE=\(shellQuoted(wine))")
        }

        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            guard key != "PATH", key != "WINE" else { continue }
            guard key.isShellEnvironmentKey else { continue }
            lines.append("export \(key)=\(shellQuoted(value))")
        }

        lines.append("alias wine64='wine'")
        return lines.joined(separator: "; ")
    }

    private func shellQuoted(_ value: String) -> String {
        value.shellQuoted
    }

    private func escapeAppleScriptString(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

public struct BottleAdvancedConfigSnapshot: Sendable {
    public var buildVersion: Int
    public var retinaMode: Bool
    public var dpi: Int
    public var mouseFixEnabled: Bool

    public init(
        buildVersion: Int,
        retinaMode: Bool,
        dpi: Int,
        mouseFixEnabled: Bool = false
    ) {
        self.buildVersion = buildVersion
        self.retinaMode = retinaMode
        self.dpi = dpi
        self.mouseFixEnabled = mouseFixEnabled
    }
}
