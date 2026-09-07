import Foundation
import ScotchDomain
import ScotchInfrastructure

public actor UninstallService: UninstallServiceProtocol {
    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let logger: AppLogger
    private let processRunner: ProcessRunner
    private let bottleRepository: BottleRepositoryProtocol
    private let runtimeService: WineRuntimeServiceProtocol
    private let installLedger: InstallLedgerProtocol

    public init(
        paths: AppPaths,
        fileSystem: LocalFileSystem,
        logger: AppLogger,
        processRunner: ProcessRunner,
        bottleRepository: BottleRepositoryProtocol,
        runtimeService: WineRuntimeServiceProtocol,
        installLedger: InstallLedgerProtocol
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.logger = logger
        self.processRunner = processRunner
        self.bottleRepository = bottleRepository
        self.runtimeService = runtimeService
        self.installLedger = installLedger
    }

    public func preview(includeBottles: Bool, includeAppBundle: Bool) async -> UninstallPlan {
        var targets: [UninstallTarget] = []

        targets.append(contentsOf: managedSupportTargets())
        targets.append(contentsOf: await temporaryTargets())
        targets.append(cliTarget())
        targets.append(contentsOf: preferenceTargets())
        targets.append(target(at: paths.thumbnailContainerDirectory, kind: .leftover))

        for entry in await installLedger.entries() {
            if entry.kind == .bottle, !includeBottles { continue }
            if entry.kind == .appBundle, !includeAppBundle { continue }
            targets.append(target(at: URL(fileURLWithPath: entry.path), kind: entry.kind))
        }

        if includeBottles {
            let bottles = await bottleRepository.loadBottles()
            let supportPath = paths.applicationSupportDirectory.path(percentEncoded: false)
            for bottle in bottles {
                let bottlePath = bottle.directoryURL.path(percentEncoded: false)
                if bottlePath.hasPrefix(supportPath) {
                    continue
                }
                targets.append(target(at: bottle.directoryURL, kind: .bottle))
            }
        }

        if includeAppBundle, let appBundle = Self.packagedAppBundleURL() {
            targets.append(target(at: appBundle, kind: .appBundle))
        }

        let unique = deduplicated(targets)
        return UninstallPlan(targets: unique, includeBottles: includeBottles, includeAppBundle: includeAppBundle)
    }

    public func perform(_ plan: UninstallPlan) async throws -> UninstallResult {
        await killAllWineProcesses()

        var result = UninstallResult()
        var appBundleURL: URL?

        for item in plan.existingTargets {
            let url = URL(fileURLWithPath: item.path)
            if item.kind == .appBundle {
                appBundleURL = url
                continue
            }
            if item.kind == .cli {
                if await removeCommandLineTool() {
                    result.removedPaths.append(item.path)
                } else {
                    result.errors.append("Could not remove \(item.path). You may need to delete it manually.")
                }
                continue
            }

            do {
                if fileSystem.fileExists(at: url) {
                    try fileSystem.removeItem(at: url)
                    result.removedPaths.append(item.path)
                } else {
                    result.skippedPaths.append(item.path)
                }
            } catch {
                let message = error.localizedDescription
                if item.kind == .leftover, message.localizedCaseInsensitiveContains("permission") {
                    logger.warning("Skipped \(item.path): \(message)")
                    result.skippedPaths.append(item.path)
                } else {
                    result.errors.append("\(item.path): \(message)")
                }
            }
        }

        if let appBundleURL, plan.includeAppBundle {
            scheduleAppBundleRemoval(appBundleURL)
            result.scheduledAppBundleRemoval = true
            result.removedPaths.append(appBundleURL.path(percentEncoded: false))
        }

        logger.info("Uninstall removed \(result.removedPaths.count) path(s) with \(result.errors.count) error(s)")
        return result
    }

    private func managedSupportTargets() -> [UninstallTarget] {
        [
            target(at: paths.applicationSupportDirectory, kind: .runtime),
            target(at: paths.legacyContainerDirectory, kind: .leftover),
            target(at: paths.legacyLogsDirectory, kind: .logs),
            target(at: paths.cachesDirectory, kind: .cache),
            target(at: paths.commandCacheDirectory, kind: .cache),
            target(at: paths.commandHTTPStorageDirectory, kind: .cache),
            target(at: paths.appHTTPStorageDirectory, kind: .cache),
            target(at: paths.thumbnailContainerDirectory, kind: .leftover),
            target(at: paths.thumbnailApplicationScriptsDirectory, kind: .leftover),
            target(at: paths.savedStateDirectory, kind: .leftover)
        ]
    }

    private func preferenceTargets() -> [UninstallTarget] {
        [target(at: paths.preferencesURL, kind: .preferences)]
    }

    private func cliTarget() -> UninstallTarget {
        target(at: paths.commandLineToolURL, kind: .cli)
    }

    private func temporaryTargets() async -> [UninstallTarget] {
        var urls: [URL] = [
            paths.gpuSpoofLogURL,
            FileManager.default.temporaryDirectory.appending(path: "ScotchRuntimeDownloads"),
            FileManager.default.temporaryDirectory.appending(path: "ScotchOverlays"),
            FileManager.default.temporaryDirectory.appending(path: "ScotchSteamInstall"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/winetricks")
        ]

        if let cacheRoot = await darwinUserCacheDirectory() {
            urls.append(cacheRoot.appending(path: "d3dm"))
            urls.append(cacheRoot.appending(path: "dxmt"))
        }

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: paths.applicationSupportDirectory.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ) {
            let prefix = "\(paths.bundleIdentifier)-runtime-backup-"
            urls.append(contentsOf: contents.filter { $0.lastPathComponent.hasPrefix(prefix) })
        }

        return urls.map { target(at: $0, kind: $0.pathExtension == "log" || $0.lastPathComponent.contains("Scotch") ? .temporary : .cache) }
    }

    private func target(at url: URL, kind: UninstallTarget.Kind) -> UninstallTarget {
        let path = url.path(percentEncoded: false)
        let exists = fileSystem.fileExists(at: url)
        return UninstallTarget(
            path: path,
            kind: kind,
            exists: exists,
            byteCount: exists ? byteCount(of: url) : 0
        )
    }

    private func byteCount(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        )
        var total: Int64 = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    private func deduplicated(_ targets: [UninstallTarget]) -> [UninstallTarget] {
        var seen = Set<String>()
        var unique: [UninstallTarget] = []
        for target in targets {
            if seen.insert(target.path).inserted {
                unique.append(target)
            }
        }
        return unique.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func killAllWineProcesses() async {
        let bottles = await bottleRepository.loadBottles()
        for bottle in bottles {
            await runtimeService.killBottle(bottle, timeout: 1.5)
        }

        let names = ["wine", "wine64", "wineserver", "wine-preloader", "wine64-preloader"]
        for name in names {
            let spec = ProcessSpecification(
                executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
                arguments: ["-9", name],
                displayName: "killall \(name)",
                timeout: 5
            )
            _ = try? await processRunner.captureProcess(spec, outputFileHandle: nil)
        }
    }

    private func removeCommandLineTool() async -> Bool {
        let url = paths.commandLineToolURL
        guard fileSystem.fileExists(at: url) else { return true }

        do {
            try fileSystem.removeItem(at: url)
            return true
        } catch {
            logger.warning("Unprivileged CLI removal failed: \(error.localizedDescription)")
        }

        let command = "rm -f \(url.path(percentEncoded: false).shellQuoted)"
        let script = "do shell script \(command.shellQuoted) with administrator privileges"
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script],
            displayName: "osascript remove scotch",
            timeout: 120
        )
        do {
            _ = try await processRunner.captureProcess(spec, outputFileHandle: nil)
            return !fileSystem.fileExists(at: url)
        } catch {
            logger.warning("Privileged CLI removal failed: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleAppBundleRemoval(_ appBundleURL: URL) {
        let path = appBundleURL.path(percentEncoded: false).shellQuoted
        let command = "sleep 2; /bin/rm -rf \(path)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.warning("Failed to schedule app bundle removal: \(error.localizedDescription)")
        }
    }

    private func darwinUserCacheDirectory() async -> URL? {
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/getconf"),
            arguments: ["DARWIN_USER_CACHE_DIR"],
            displayName: "getconf",
            timeout: 5
        )
        guard let output = try? await processRunner.captureProcess(spec, outputFileHandle: nil) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    nonisolated public static func packagedAppBundleURL() -> URL? {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return nil }
        guard bundleURL.pathExtension == "app" else { return nil }
        return bundleURL
    }
}
