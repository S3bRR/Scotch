import Foundation
import Darwin
import CryptoKit
import ScotchDomain
import ScotchInfrastructure

public enum RuntimeUpdateError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}

public enum RuntimeFeedVerifier {
    public static func decode(_ data: Data, publicKey: String, now: Date = Date()) throws -> RuntimeUpdateFeed {
        let envelope = try JSONDecoder().decode(SignedUpdateEnvelope.self, from: data)
        guard let payload = Data(base64Encoded: envelope.payload), payload.count < 1_000_000,
              let signature = Data(base64Encoded: envelope.signature),
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: payload) else { throw RuntimeUpdateError.invalid("Runtime update signature is invalid. Your installed runtime has not changed.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feed = try decoder.decode(RuntimeUpdateFeed.self, from: payload)
        guard feed.schemaVersion == 1, feed.revision > 0, feed.validUntil > now else {
            throw RuntimeUpdateError.invalid("The runtime feed is expired or requires a newer Scotch version.")
        }
        guard Set(feed.sets.map(\.id)).count == feed.sets.count else { throw RuntimeUpdateError.invalid("Duplicate runtime set IDs") }
        for set in feed.sets {
            guard ApprovedRuntimeSet.validID(set.id), set.architecture == "arm64", set.minimumAppBuild > 0,
                  set.minimumMacOS >= 26, set.packages.count >= 4,
                  Set(set.packages.map(\.component)).count == set.packages.count,
                  [RuntimeComponent.wine, .dxvk, .dxmt, .zink].allSatisfy({ set.package($0) != nil }) else {
                throw RuntimeUpdateError.invalid("Unsupported or incomplete runtime set")
            }
            for package in set.packages {
                let validLayout: Bool
                switch package.component {
                case .d3dmetal: validLayout = package.layoutVersion == 3 && set.minimumAppBuild >= 12
                case .dxmt: validLayout = package.layoutVersion == 2 && set.minimumAppBuild >= 12
                default: validLayout = (package.layoutVersion ?? 1) == 1
                }
                let futureClient = set.minimumAppBuild > (Int(ScotchAppInfo.build) ?? 0)
                let layoutAccepted = futureClient ? (package.layoutVersion ?? 1) > 0 : validLayout
                guard layoutAccepted, package.url.scheme == "https", package.url.user == nil, package.url.password == nil,
                      package.url.host == "github.com", package.url.path.contains("/releases/download/"),
                      !package.version.isEmpty, package.size > 0,
                      package.fileName == URL(fileURLWithPath: package.fileName).lastPathComponent,
                      !package.fileName.hasPrefix("."), !package.fileName.contains("\\"),
                      package.sha256.count == 64, package.sha256.allSatisfy(\.isHexDigit) else {
                    throw RuntimeUpdateError.invalid("Invalid runtime package metadata")
                }
            }
        }
        return feed
    }
}

public actor RuntimeUpdateService {
    private let paths: AppPaths
    private let network: NetworkClient
    private let runner: ProcessRunner
    private let logger: AppLogger
    private let feedURL: URL
    private let publicKey: String
    private let activity: UpdateActivity
    private var busy = false
    private var cacheURL: URL { paths.cachesDirectory.appending(path: "RuntimeFeed.json") }
    private var revisionURL: URL { paths.applicationSupportDirectory.appending(path: "RuntimeFeedRevision.plist") }

    public init(paths: AppPaths, network: NetworkClient, logger: AppLogger,
                runner: ProcessRunner = DefaultProcessRunner(), feedURL: URL = UpdateConfiguration.runtimeFeedURL,
                publicKey: String = UpdateConfiguration.runtimePublicKey, activity: UpdateActivity = .shared) {
        self.paths = paths; self.network = network; self.logger = logger
        self.runner = runner; self.feedURL = feedURL; self.publicKey = publicKey; self.activity = activity
    }

    public func check(force: Bool = false) async throws -> RuntimeCheckResult {
        guard !busy else { throw RuntimeUpdateError.invalid("A runtime operation is already in progress.") }
        busy = true
        defer { busy = false }
        let fm = FileManager.default
        let modified = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let data: Data
        if !force, let modified, Date().timeIntervalSince(modified) < 86_400, let cached = try? Data(contentsOf: cacheURL) {
            data = cached
        } else {
            do { data = try await network.data(for: NetworkRequest(url: feedURL, timeout: 30)) }
            catch let NetworkClientError.nonSuccessStatus(_, status) where status == 404 {
                throw RuntimeUpdateError.invalid("The approved runtime feed has not been published yet. Your installed runtime is unchanged.")
            }
        }
        let feed = try RuntimeFeedVerifier.decode(data, publicKey: publicKey)
        let highest = (try? PropertyListDecoder().decode([String: Int].self, from: Data(contentsOf: revisionURL))["revision"]) ?? 0
        guard feed.revision >= highest else { throw RuntimeUpdateError.invalid("An older runtime feed was rejected.") }
        try fm.createDirectory(at: paths.cachesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.applicationSupportDirectory, withIntermediateDirectories: true)
        // Cache only authenticated metadata. Keep the highest revision in durable app data.
        if (try? Data(contentsOf: cacheURL)) != data { try data.write(to: cacheURL, options: .atomic) }
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: cacheURL.path)
        try PropertyListEncoder().encode(["revision": feed.revision]).write(to: revisionURL, options: .atomic)
        guard !feed.sets.isEmpty else { return .current }
        if let newest = feed.sets.last,
           newest.minimumAppBuild > (Int(ScotchAppInfo.build) ?? 0) || newest.minimumMacOS > ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
            return .incompatible("A newer approved runtime requires a newer Scotch or macOS version. App updates will be checked in the same Update flow.")
        }
        guard let target = feed.sets.last(where: { $0.minimumAppBuild <= (Int(ScotchAppInfo.build) ?? 0) && $0.minimumMacOS <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion }) else {
            return .incompatible("The approved runtime requires a newer Scotch or macOS version. App updates will be checked in the same Update flow.")
        }
        if paths.defaultRuntimeSetID == target.id {
            let inspector = makeInstaller(paths: paths.forRuntimeSet(target.id), target: target)
            return await inspector.isRuntimeInstalled() ? .current : .repair(target)
        }
        return .available(target)
    }

    /// Installs beside the existing runtime. Existing bottles keep their selected
    /// runtime; the new default applies to newly created bottles only.
    public func install(_ target: ApprovedRuntimeSet) async throws {
        guard !busy else { throw RuntimeUpdateError.invalid("A runtime operation is already in progress.") }
        busy = true
        defer { busy = false }
        // Reauthenticate current feed and membership: never accept a stale UI object.
        let data = try await network.data(for: NetworkRequest(url: feedURL, timeout: 30))
        let feed = try RuntimeFeedVerifier.decode(data, publicKey: publicKey)
        let highest = (try? PropertyListDecoder().decode([String: Int].self, from: Data(contentsOf: revisionURL))["revision"]) ?? 0
        guard feed.revision >= highest, feed.sets.contains(target), target.minimumAppBuild <= (Int(ScotchAppInfo.build) ?? 0), target.minimumMacOS <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion else {
            throw RuntimeUpdateError.invalid("This runtime update is no longer approved or is incompatible.")
        }
        let lease = try activity.acquireMaintenance()
        defer { withExtendedLifetime(lease) {} }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.runtimeSetsDirectory, withIntermediateDirectories: true)
        let final = paths.forRuntimeSet(target.id)
        let hadExisting = fm.fileExists(atPath: final.librariesDirectory.path)
        var needsStaging = true
        if hadExisting {
            guard let recorded = try? JSONDecoder().decode(ApprovedRuntimeSet.self, from: Data(contentsOf: final.librariesDirectory.appending(path: "RuntimeSet.json"))), recorded == target else {
                throw RuntimeUpdateError.invalid("An existing runtime set has different contents. Runtime IDs are immutable.")
            }
            let inspector = makeInstaller(paths: final, target: target)
            needsStaging = !(await inspector.isRuntimeInstalled())
        }
        if needsStaging {
            // Abandoned stages are not selected or used. Clean them only while exclusive.
            for old in try fm.contentsOfDirectory(at: paths.runtimeSetsDirectory, includingPropertiesForKeys: nil) where old.lastPathComponent.hasPrefix("staging-") {
                try? fm.removeItem(at: old)
            }
            var staged = paths
            staged.runtimeDirectoryOverride = paths.runtimeSetsDirectory.appending(path: "staging-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: staged.librariesDirectory) }
            let installer = makeInstaller(paths: staged, target: target)
            let releases = try await installer.fetchLatestReleases()
            let archives = try await installer.downloadAll(releases: releases, progress: nil)
            _ = try await installer.installAll(from: archives)
            // Verify that the approved Wine build can run on this Mac without
            // initializing or modifying any user's prefix.
            let output = try await runner.captureProcess(ProcessSpecification(
                executableURL: staged.wineBinaryURL, arguments: ["--version"],
                environment: ["WINEPREFIX": staged.librariesDirectory.appending(path: "smoke-prefix").path],
                displayName: "Verify Wine version", timeout: 30), outputFileHandle: nil)
            guard output.lowercased().contains("wine") else { throw RuntimeUpdateError.invalid("The approved Wine build did not pass its startup check.") }
            try JSONEncoder().encode(target).write(to: staged.librariesDirectory.appending(path: "RuntimeSet.json"), options: .atomic)
            if hadExisting {
                guard !activity.hasRunningWineProcesses else { throw UpdateActivityError.busy("Close games before activating the repaired runtime.") }
                // Atomic directory exchange: a crash cannot leave a selected
                // runtime missing between an old-directory rename and a new one.
                guard renamex_np(staged.librariesDirectory.path, final.librariesDirectory.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw RuntimeUpdateError.invalid("Unable to activate the repaired runtime. The previous files remain in place.")
                }
            } else {
                try fm.moveItem(at: staged.librariesDirectory, to: final.librariesDirectory)
            }
        }
        // One atomic pointer is the commit point. A crash before this leaves the
        // previous default selected; a crash after it leaves a verified complete set.
        try UpdateBackup.metadata(paths: paths)
        try await PlistStore().write(RuntimeSelection(defaultSetID: target.id), to: paths.runtimeSelectionURL)
        try PropertyListEncoder().encode(["revision": feed.revision]).write(to: revisionURL, options: .atomic)
    }

    public func installedSets() -> [ApprovedRuntimeSet] {
        let roots = (try? FileManager.default.contentsOfDirectory(at: paths.runtimeSetsDirectory, includingPropertiesForKeys: nil)) ?? []
        return roots.compactMap { root in
            guard !root.lastPathComponent.hasPrefix("staging-"), let data = try? Data(contentsOf: root.appending(path: "RuntimeSet.json")),
                  let set = try? JSONDecoder().decode(ApprovedRuntimeSet.self, from: data), set.id == root.lastPathComponent else { return nil }
            return set
        }.sorted { $0.title < $1.title }
    }

    private func makeInstaller(paths: AppPaths, target: ApprovedRuntimeSet) -> RuntimeInstallerService {
        RuntimeInstallerService(paths: paths, fileSystem: LocalFileSystem(), logger: logger, plistStore: PlistStore(), processRunner: runner, networkClient: network, approvedRuntime: target)
    }
}
