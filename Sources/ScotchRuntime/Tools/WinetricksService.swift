import Foundation
import ScotchDomain
import ScotchInfrastructure

public actor WinetricksService: WinetricksServiceProtocol {
    static let remoteScriptURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/f3890f670867b5ffbc3938726db45c0f7d16c8ba/src/winetricks")!
    static let coreFontVerbs = [
        "andale", "arial", "comicsans", "courier", "georgia",
        "impact", "times", "trebuchet", "verdana", "webdings"
    ]

    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let processRunner: ProcessRunner
    private let networkClient: NetworkClient

    public init(
        paths: AppPaths,
        fileSystem: LocalFileSystem,
        logger: AppLogger,
        processRunner: ProcessRunner = DefaultProcessRunner(),
        networkClient: NetworkClient = DefaultNetworkClient()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.processRunner = processRunner
        self.networkClient = networkClient
        _ = logger
    }

    public func ensureInstalled() async throws {
        if fileSystem.fileExists(at: paths.winetricksScriptURL) {
            return
        }

        if !fileSystem.fileExists(at: paths.librariesDirectory) {
            try fileSystem.createDirectory(at: paths.librariesDirectory)
        }
        if !fileSystem.fileExists(at: paths.winetricksCacheDirectory) {
            try fileSystem.createDirectory(at: paths.winetricksCacheDirectory)
        }

        let data: Data
        do {
            data = try await networkClient.data(for: NetworkRequest(url: Self.remoteScriptURL))
        } catch let NetworkClientError.nonSuccessStatus(_, status) {
            throw WinetricksError.downloadFailed("HTTP \(status)")
        } catch {
            throw WinetricksError.downloadFailed(error.localizedDescription)
        }

        try data.write(to: paths.winetricksScriptURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: paths.winetricksScriptURL.path(percentEncoded: false)
        )
    }

    public func parseVerbs() async throws -> [WinetricksCategoryListing] {
        try await ensureInstalled()
        let output = try await runHeadless(arguments: ["list-all"], bottle: nil)
        let categories = parseListAllOutput(output)
        if categories.isEmpty {
            throw WinetricksError.parseFailed("No categories found in winetricks list-all output")
        }
        return categories
    }

    public func run(command: String, in bottle: BottleSummary, mode: WinetricksExecutionMode) async throws -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            return ""
        }

        switch mode {
        case .headless:
            let arguments = trimmedCommand.split(whereSeparator: \.isWhitespace).map(String.init)
            return try await runHeadless(arguments: arguments, bottle: bottle)
        case .terminal:
            try await runInTerminal(command: trimmedCommand, bottle: bottle)
            return "Launched \(trimmedCommand) in Terminal."
        }
    }

    public func installCoreFonts(
        in bottle: BottleSummary,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        try await ensureInstalled()
        let total = Double(Self.coreFontVerbs.count)

        for (index, verb) in Self.coreFontVerbs.enumerated() {
            _ = try await runHeadless(arguments: [verb], bottle: bottle, timeout: 120)
            progress?(Double(index + 1) / total)
        }
    }

    func parseListAllOutput(_ output: String) -> [WinetricksCategoryListing] {
        var result: [WinetricksCategoryListing] = []
        var currentCategory: WinetricksCategory?
        var currentVerbs: [WinetricksVerb] = []

        func flushCurrentCategory() {
            guard let currentCategory else { return }
            result.append(WinetricksCategoryListing(category: currentCategory, verbs: currentVerbs))
            currentVerbs = []
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("=====") {
                flushCurrentCategory()
                let rawCategory = trimmed
                    .replacingOccurrences(of: "=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                currentCategory = WinetricksCategory(rawValue: rawCategory)
                continue
            }

            guard currentCategory != nil else { continue }
            let chunks = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            guard let verbName = chunks.first else { continue }
            let verbDescription = chunks.count > 1 ? chunks[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            currentVerbs.append(WinetricksVerb(name: verbName, description: verbDescription))
        }

        flushCurrentCategory()
        return result
    }

    func baseEnvironment(for bottle: BottleSummary?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathSegments: [String] = [paths.runtimeBinDirectory.path(percentEncoded: false)]

        if let cabextractDirectory = resolveCabextractDirectory() {
            pathSegments.append(cabextractDirectory.path(percentEncoded: false))
        }

        if let existingPath = environment["PATH"] {
            pathSegments.append(existingPath)
        }
        environment["PATH"] = pathSegments.joined(separator: ":")
        environment["WINE"] = "wine"
        environment["WINETRICKS_GUI"] = "none"
        environment["W_OPT_UNATTENDED"] = "1"
        environment["W_CACHE"] = paths.winetricksCacheDirectory.path(percentEncoded: false)

        if let bottle {
            environment["WINEPREFIX"] = bottle.directoryURL.path(percentEncoded: false)
        }

        return environment
    }

    private func runHeadless(arguments: [String], bottle: BottleSummary?, timeout: TimeInterval? = nil) async throws -> String {
        try await ensureInstalled()

        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: [paths.winetricksScriptURL.path(percentEncoded: false)] + arguments,
            environment: baseEnvironment(for: bottle),
            displayName: "winetricks \(arguments.joined(separator: " "))",
            timeout: timeout
        )

        do {
            return try await processRunner.captureProcess(spec, outputFileHandle: nil)
        } catch let ProcessRunnerError.timeout(_, elapsed) {
            throw WinetricksError.executionFailed("Timed out after \(Int(elapsed))s: \(arguments.joined(separator: " "))")
        } catch let ProcessRunnerError.nonZeroExit(_, _, output) {
            throw WinetricksError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw WinetricksError.executionFailed(error.localizedDescription)
        }
    }

    private func runInTerminal(command: String, bottle: BottleSummary) async throws {
        let commandString = makeTerminalCommand(command: command, bottle: bottle)
        let escapedCommand = appleScriptEscaped(commandString)
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            displayName: "osascript Terminal"
        )

        do {
            _ = try await processRunner.captureProcess(spec, outputFileHandle: nil)
        } catch let ProcessRunnerError.nonZeroExit(_, _, output) {
            throw WinetricksError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw WinetricksError.executionFailed(error.localizedDescription)
        }
    }

    private func makeTerminalCommand(command: String, bottle: BottleSummary) -> String {
        let environment = baseEnvironment(for: bottle)
        let path = environment["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        let winePrefix = bottle.directoryURL.path(percentEncoded: false)
        return "PATH=\(path.shellEscaped) WINE=wine WINEPREFIX=\(winePrefix.shellEscaped) \(paths.winetricksScriptURL.path(percentEncoded: false).shellEscaped) \(command)"
    }

    private func resolveCabextractDirectory() -> URL? {
        if let mainBundleCabextract = Bundle.main.url(forResource: "cabextract", withExtension: nil)?.deletingLastPathComponent() {
            return mainBundleCabextract
        }
        if let moduleCabextract = Bundle.module.url(forResource: "cabextract", withExtension: nil)?.deletingLastPathComponent() {
            return moduleCabextract
        }

        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/cabextract"),
            URL(fileURLWithPath: "/usr/local/bin/cabextract")
        ]

        for candidate in candidates where fileSystem.fileExists(at: candidate) {
            return candidate.deletingLastPathComponent()
        }
        return nil
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

