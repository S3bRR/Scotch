import Foundation
import Darwin
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime

@main
struct ScotchCmdMain {
    static func main() async {
        let tool = ScotchCommandLine()
        let exitCode = await tool.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Darwin.exit(exitCode)
    }
}

struct ScotchCommandLine {
    let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch")
    let encoder = PropertyListEncoder()
    let decoder = PropertyListDecoder()
    let processRunner: ProcessRunner

    init(processRunner: ProcessRunner = DefaultProcessRunner()) {
        self.processRunner = processRunner
        encoder.outputFormat = .xml
    }

    func run(arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            printUsage()
            return 1
        }

        switch command {
        case "list":
            return listBottles()
        case "create":
            guard arguments.count >= 2 else { return fail("Missing bottle name.") }
            return createBottle(named: arguments[1])
        case "add":
            guard arguments.count >= 2 else { return fail("Missing bottle path.") }
            return addBottle(path: arguments[1])
        case "install":
            return installCommandLink()
        case "uninstall":
            return uninstallCommandLink()
        case "remove":
            guard arguments.count >= 2 else { return fail("Missing bottle name.") }
            return removeBottle(named: arguments[1], deleteFiles: false)
        case "delete":
            guard arguments.count >= 2 else { return fail("Missing bottle name.") }
            return removeBottle(named: arguments[1], deleteFiles: true)
        case "shellenv":
            guard arguments.count >= 2 else { return fail("Missing bottle name.") }
            return printShellEnvironment(for: arguments[1])
        case "run":
            guard arguments.count >= 3 else { return fail("Usage: ScotchCmd run <bottle-name> <exe-path> [args...]") }
            let bottleName = arguments[1]
            let executablePath = arguments[2]
            let executableArguments = Array(arguments.dropFirst(3))
            return await runProgram(in: bottleName, executablePath: executablePath, executableArguments: executableArguments)
        case "help", "--help", "-h":
            printUsage()
            return 0
        default:
            return fail("Unknown command '\(command)'.")
        }
    }

    private func listBottles() -> Int32 {
        let bottles = loadBottles()
        if bottles.isEmpty {
            print("No bottles found.")
            return 0
        }

        print("Name\tWindows Version\tPath")
        for bottle in bottles {
            let row = [
                bottle.settings.info.name,
                bottle.settings.wine.windowsVersion.displayName,
                bottle.directoryURL.path(percentEncoded: false)
            ].joined(separator: "\t")
            print(row)
        }
        return 0
    }

    private func addBottle(path: String) -> Int32 {
        let bottleURL = URL(fileURLWithPath: path)
        let metadata = bottleURL.appending(path: BottleSettings.metadataFileName)
        guard FileManager.default.fileExists(atPath: metadata.path(percentEncoded: false)) else {
            return fail("Not a valid bottle folder (missing Metadata.plist).")
        }

        var catalog = loadCatalog()
        let normalizedPath = bottleURL.path(percentEncoded: false)
        if catalog.bottlePaths.contains(normalizedPath) {
            print("Bottle already exists in catalog.")
            return 0
        }

        catalog.bottlePaths.append(normalizedPath)
        guard saveCatalog(catalog) else {
            return fail("Failed to persist bottle catalog.")
        }

        print("Added bottle: \(normalizedPath)")
        return 0
    }

    private func createBottle(named name: String) -> Int32 {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fail("Bottle name cannot be empty.")
        }

        do {
            if !FileManager.default.fileExists(atPath: paths.defaultBottlesDirectory.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: paths.defaultBottlesDirectory, withIntermediateDirectories: true)
            }

            let bottleURL = paths.defaultBottlesDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: bottleURL, withIntermediateDirectories: true)

            var settings = BottleSettings()
            settings.info.name = name
            let metadataData = try encoder.encode(settings)
            try metadataData.write(to: bottleURL.appending(path: BottleSettings.metadataFileName))

            var catalog = loadCatalog()
            catalog.bottlePaths.append(bottleURL.path(percentEncoded: false))
            guard saveCatalog(catalog) else {
                try? FileManager.default.removeItem(at: bottleURL)
                return fail("Failed to persist bottle catalog.")
            }

            print("Created bottle '\(name)' at \(bottleURL.path(percentEncoded: false)).")
            return 0
        } catch {
            return fail("Failed to create bottle: \(error.localizedDescription)")
        }
    }

    private func installCommandLink() -> Int32 {
        guard let executableURL = Bundle.main.executableURL else {
            return fail("Unable to resolve executable path.")
        }

        let targetURL = URL(fileURLWithPath: "/usr/local/bin/scotch")
        do {
            if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.createSymbolicLink(
                at: targetURL,
                withDestinationURL: executableURL
            )
            print("Installed command link at \(targetURL.path(percentEncoded: false)).")
            return 0
        } catch {
            return fail("Failed to install command link: \(error.localizedDescription)")
        }
    }

    private func uninstallCommandLink() -> Int32 {
        let targetURL = URL(fileURLWithPath: "/usr/local/bin/scotch")
        do {
            guard FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) else {
                print("Command link is not installed.")
                return 0
            }
            try FileManager.default.removeItem(at: targetURL)
            print("Removed command link at \(targetURL.path(percentEncoded: false)).")
            return 0
        } catch {
            return fail("Failed to remove command link: \(error.localizedDescription)")
        }
    }

    private func removeBottle(named name: String, deleteFiles: Bool) -> Int32 {
        var catalog = loadCatalog()
        guard let index = indexOfBottle(named: name, in: catalog) else {
            return fail("Bottle '\(name)' not found.")
        }

        let path = catalog.bottlePaths[index]
        catalog.bottlePaths.remove(at: index)
        guard saveCatalog(catalog) else {
            return fail("Failed to persist bottle catalog.")
        }

        if deleteFiles {
            do {
                try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            } catch {
                return fail("Removed from catalog, but failed to delete files: \(error.localizedDescription)")
            }
            print("Deleted bottle '\(name)'.")
        } else {
            print("Removed bottle '\(name)' from catalog.")
        }
        return 0
    }

    private func printShellEnvironment(for bottleName: String) -> Int32 {
        guard let bottle = findBottle(named: bottleName) else {
            return fail("Bottle '\(bottleName)' not found.")
        }

        let assembler = EnvironmentAssembler(paths: paths)
        let environment = assembler.makeShellEnvironment(bottle: bottle)
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            print("export \(key)=\(shellQuoted(value))")
        }
        print("alias wine64='wine'")
        return 0
    }

    func runProgram(in bottleName: String, executablePath: String, executableArguments: [String]) async -> Int32 {
        guard let bottle = findBottle(named: bottleName) else {
            return fail("Bottle '\(bottleName)' not found.")
        }

        let executableURL = URL(fileURLWithPath: executablePath)
        let assembler = EnvironmentAssembler(paths: paths)
        let environment = assembler.makeWineEnvironment(bottle: bottle)

        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: [
                "-a",
                paths.wineBundleURL.path(percentEncoded: false),
                "--args",
                "start",
                "/unix",
                executableURL.path(percentEncoded: false)
            ] + executableArguments,
            environment: environment,
            displayName: "scotch run"
        )

        do {
            _ = try await processRunner.captureProcess(spec, outputFileHandle: nil)
            return 0
        } catch let ProcessRunnerError.nonZeroExit(_, status, _) {
            return status
        } catch {
            return fail("Failed to run executable: \(error.localizedDescription)")
        }
    }

    private func loadCatalog() -> BottleCatalog {
        if let data = try? Data(contentsOf: paths.bottleCatalogURL),
           let decoded = try? decoder.decode(BottleCatalog.self, from: data) {
            return decoded
        }

        if paths.alternateBottleCatalogURL != paths.bottleCatalogURL,
           let data = try? Data(contentsOf: paths.alternateBottleCatalogURL),
           let decoded = try? decoder.decode(BottleCatalog.self, from: data) {
            return decoded
        }

        return BottleCatalog()
    }

    private func saveCatalog(_ catalog: BottleCatalog) -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: paths.containerDirectory.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: paths.containerDirectory, withIntermediateDirectories: true)
            }

            let data = try encoder.encode(catalog)
            try data.write(to: paths.bottleCatalogURL)
            if paths.alternateBottleCatalogURL != paths.bottleCatalogURL {
                try? data.write(to: paths.alternateBottleCatalogURL)
            }
            return true
        } catch {
            return false
        }
    }

    private func loadBottles() -> [BottleSummary] {
        let catalog = loadCatalog()
        return catalog.bottlePaths.compactMap { rawPath in
            let directory = URL(fileURLWithPath: rawPath)
            let metadata = directory.appending(path: BottleSettings.metadataFileName)
            guard let data = try? Data(contentsOf: metadata),
                  let settings = try? decoder.decode(BottleSettings.self, from: data) else {
                return nil
            }
            return BottleSummary(
                id: BottleID(rawValue: directory.lastPathComponent),
                directoryURL: directory,
                settings: settings,
                isAvailable: true
            )
        }
        .sorted { lhs, rhs in
            lhs.settings.info.name.localizedCaseInsensitiveCompare(rhs.settings.info.name) == .orderedAscending
        }
    }

    private func findBottle(named name: String) -> BottleSummary? {
        loadBottles().first { $0.settings.info.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func indexOfBottle(named name: String, in catalog: BottleCatalog) -> Int? {
        for (index, rawPath) in catalog.bottlePaths.enumerated() {
            let directory = URL(fileURLWithPath: rawPath)
            let metadata = directory.appending(path: BottleSettings.metadataFileName)
            guard let data = try? Data(contentsOf: metadata),
                  let settings = try? decoder.decode(BottleSettings.self, from: data) else {
                continue
            }
            if settings.info.name.caseInsensitiveCompare(name) == .orderedSame {
                return index
            }
        }
        return nil
    }

    private func fail(_ message: String) -> Int32 {
        fputs("ScotchCmd: \(message)\n", stderr)
        return 1
    }

    private func printUsage() {
        print(
            """
            ScotchCmd usage:
              ScotchCmd list
              ScotchCmd create <bottle-name>
              ScotchCmd add <bottle-path>
              ScotchCmd install
              ScotchCmd uninstall
              ScotchCmd remove <bottle-name>
              ScotchCmd delete <bottle-name>
              ScotchCmd shellenv <bottle-name>
              ScotchCmd run <bottle-name> <exe-path> [args...]
            """
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
