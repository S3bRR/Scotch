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

        let bottles = await bottleRepository.loadBottles()
        targets.append(contentsOf: wineServerSocketTargets(for: bottles))

        if includeBottles {
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
        await unregisterSystemIntegrations(removingAppBundle: plan.includeAppBundle)

        var result = UninstallResult()
        var appBundleURL: URL?
        var retryAfterExit: [URL] = []

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
                    logger.warning("Deferring \(item.path) until Scotch exits: \(message)")
                    retryAfterExit.append(url)
                    result.skippedPaths.append(item.path)
                } else {
                    result.errors.append("\(item.path): \(message)")
                }
            }
        }

        await flushPreferences()
        // Only Scotch's server directories were removed above; drop the parent
        // when no other Wine install is using it.
        if (try? FileManager.default.contentsOfDirectory(atPath: Self.wineServerRoot.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: Self.wineServerRoot)
        }

        // macOS writes saved window state on quit, so clear it again afterwards.
        retryAfterExit.append(paths.savedStateDirectory)
        let removingAppBundle = plan.includeAppBundle ? appBundleURL : nil
        scheduleCleanupAfterExit(appBundle: removingAppBundle, retrying: retryAfterExit)
        if let removingAppBundle {
            result.scheduledAppBundleRemoval = true
            result.removedPaths.append(removingAppBundle.path(percentEncoded: false))
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

    /// Identities Scotch runs code under besides its own: the generated Wine.app
    /// launcher and the QuickLook thumbnail extension.
    private var relatedBundleIdentifiers: [String] {
        ["\(paths.bundleIdentifier).WineBundle", "\(paths.bundleIdentifier).Thumbnail"]
    }

    private func preferenceTargets() -> [UninstallTarget] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        var targets = [target(at: paths.preferencesURL, kind: .preferences)]
        for identifier in relatedBundleIdentifiers {
            targets.append(target(at: library.appending(path: "Preferences/\(identifier).plist"), kind: .preferences))
            targets.append(target(at: library.appending(path: "Saved Application State/\(identifier).savedState"), kind: .leftover))
            targets.append(target(at: library.appending(path: "Caches/\(identifier)"), kind: .cache))
            targets.append(target(at: library.appending(path: "HTTPStorages/\(identifier)"), kind: .cache))
        }
        return targets
    }

    /// Wine keeps one server socket directory per prefix, named after the prefix
    /// directory's device and inode, so it has to be found before bottles are deleted.
    private func wineServerSocketTargets(for bottles: [BottleSummary]) -> [UninstallTarget] {
        bottles.compactMap { bottle in
            var info = stat()
            guard stat(bottle.directoryURL.path(percentEncoded: false), &info) == 0 else { return nil }
            let device = String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16)
            let inode = String(UInt64(info.st_ino), radix: 16)
            return target(at: Self.wineServerRoot.appending(path: "server-\(device)-\(inode)"), kind: .temporary)
        }
    }

    private static var wineServerRoot: URL {
        URL(fileURLWithPath: "/tmp/.wine-\(getuid())")
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

        // Metal shader caches land under the process's bundle identifier; Wine
        // processes outside Wine.app use Wine's own identifier.
        let identities = [paths.bundleIdentifier, "org.winehq.wine"] + relatedBundleIdentifiers
        if let cacheRoot = await darwinUserDirectory("DARWIN_USER_CACHE_DIR") {
            urls.append(cacheRoot.appending(path: "d3dm"))
            urls.append(cacheRoot.appending(path: "dxmt"))
            urls.append(contentsOf: identities.map { cacheRoot.appending(path: $0) })
        }
        if let tempRoot = await darwinUserDirectory("DARWIN_USER_TEMP_DIR") {
            urls.append(contentsOf: identities.map { tempRoot.appending(path: $0) })
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

    /// Stops the QuickLook extension (macOS refuses to delete a container in use)
    /// and drops Scotch's apps from LaunchServices so they leave "Open With" menus.
    private func unregisterSystemIntegrations(removingAppBundle: Bool) async {
        if removingAppBundle, let appBundle = Self.packagedAppBundleURL() {
            let appex = appBundle.appending(path: "Contents/PlugIns/ScotchThumbnail.appex")
            await runQuietly("/usr/bin/pluginkit", ["-r", appex.path(percentEncoded: false)])
        }
        await runQuietly("/usr/bin/killall", ["ScotchThumbnail"])
        await runQuietly(Self.lsregisterPath, ["-u", paths.wineBundleURL.path(percentEncoded: false)])
    }

    /// Deleting a preferences plist is not enough: cfprefsd keeps a cached copy and
    /// writes it back. `defaults delete` clears both.
    private func flushPreferences() async {
        for domain in [paths.bundleIdentifier] + relatedBundleIdentifiers {
            await runQuietly("/usr/bin/defaults", ["delete", domain])
        }
    }

    private func runQuietly(_ executable: String, _ arguments: [String]) async {
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            displayName: URL(fileURLWithPath: executable).lastPathComponent,
            timeout: 10
        )
        _ = try? await processRunner.captureProcess(spec, outputFileHandle: nil)
    }

    private static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Runs once Scotch has exited: removes the app bundle (it can't delete itself
    /// while running), retries paths macOS refused while it was alive, and clears
    /// preferences and saved state that AppKit writes during quit.
    private func scheduleCleanupAfterExit(appBundle: URL?, retrying retryPaths: [URL]) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var steps = ["while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.5; done", "sleep 1"]
        for url in retryPaths {
            steps.append("/bin/rm -rf \(url.path(percentEncoded: false).shellQuoted)")
        }
        for domain in [paths.bundleIdentifier] + relatedBundleIdentifiers {
            steps.append("/usr/bin/defaults delete \(domain.shellQuoted) 2>/dev/null")
        }
        if let appBundle {
            let path = appBundle.path(percentEncoded: false).shellQuoted
            steps.append("\(Self.lsregisterPath.shellQuoted) -u \(path)")
            steps.append("/bin/rm -rf \(path)")
        }
        let command = steps.joined(separator: "; ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.warning("Failed to schedule cleanup after exit: \(error.localizedDescription)")
        }
    }

    private func darwinUserDirectory(_ name: String) async -> URL? {
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/getconf"),
            arguments: [name],
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
