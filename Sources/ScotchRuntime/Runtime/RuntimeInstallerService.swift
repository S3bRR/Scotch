import Foundation
import Darwin
import ScotchDomain
import ScotchInfrastructure

public actor RuntimeInstallerService: RuntimeInstallerProtocol {
    private enum OverlayVersion {
        /// Gcenx Wine 11.16 is built `--without-opengl`. The 11.6 byte patch
        /// must not be overlaid onto a different winemac.so.
        static let winemac = "stock-11.16"
        static let d3dmetal = D3DMetalInstallation.version
        static let zink = "mesa-26.2.0"
    }


    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let logger: AppLogger
    private let plistStore: PlistStore
    private let processRunner: ProcessRunner
    private let networkClient: NetworkClient
    private let installSession = UUID().uuidString
    private var scratchRoot: URL { paths.applicationSupportDirectory.appending(path: "InstallSessions/" + installSession) }
    private var downloadsRoot: URL { FileManager.default.temporaryDirectory.appending(path: "ScotchRuntimeDownloads/" + installSession) }
    private let approvedRuntime: ApprovedRuntimeSet?

    public init(
        paths: AppPaths,
        fileSystem: LocalFileSystem,
        logger: AppLogger,
        plistStore: PlistStore,
        processRunner: ProcessRunner,
        networkClient: NetworkClient = DefaultNetworkClient(),
        approvedRuntime: ApprovedRuntimeSet? = nil
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.logger = logger
        self.plistStore = plistStore
        self.processRunner = processRunner
        self.networkClient = networkClient
        self.approvedRuntime = approvedRuntime
    }

    public func isRuntimeInstalled() async -> Bool {
        await currentManifest() != nil
    }

    public func currentManifest() async -> RuntimeManifest? {
        do {
            var manifest = try await plistStore.read(RuntimeManifest.self, from: paths.runtimeManifestURL)
            try validateManifest(manifest)
            try verifyInstalledArtifacts()
            if manifest.d3dmetalVersion != nil, (try? verifyOverlayInstall(component: .d3dmetal)) == nil {
                // A damaged optional backend must not disable the other backends.
                manifest.d3dmetalVersion = nil
            }
            return manifest
        } catch {
            return nil
        }
    }

    public func fetchLatestReleases() async throws -> RuntimeReleases {
        if let approvedRuntime, let wine = approvedRuntime.package(.wine), let dxvk = approvedRuntime.package(.dxvk), let dxmt = approvedRuntime.package(.dxmt) {
            return RuntimeReleases(wine: wine.asset, dxvk: dxvk.asset, dxmt: dxmt.asset)
        }
        return RuntimeReleases(wine: RuntimeAssets.wine, dxvk: RuntimeAssets.dxvk, dxmt: RuntimeAssets.dxmt)
    }

    public func downloadAll(
        releases: RuntimeReleases,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> DownloadedRuntimeArchives {
        let temp = downloadsRoot
        if fileSystem.fileExists(at: temp) {
            try fileSystem.removeItem(at: temp)
        }
        try fileSystem.createDirectory(at: temp)

        let totalBytes = max(releases.wine.size + releases.dxvk.size + releases.dxmt.size, 1)
        let progressCounter = DownloadProgressCounter(total: totalBytes)

        async let wineURL = downloadAsset(releases.wine, into: temp) { downloaded in
            progress?(progressCounter.advance(by: downloaded))
        }
        async let dxvkURL = downloadAsset(releases.dxvk, into: temp) { downloaded in
            progress?(progressCounter.advance(by: downloaded))
        }
        async let dxmtURL = downloadAsset(releases.dxmt, into: temp) { downloaded in
            progress?(progressCounter.advance(by: downloaded))
        }

        return DownloadedRuntimeArchives(
            runtimeReleases: releases,
            wineArchive: try await wineURL,
            dxvkArchive: try await dxvkURL,
            dxmtArchive: try await dxmtURL
        )
    }

    public func installAll(from archives: DownloadedRuntimeArchives) async throws -> (RuntimeManifest, [OverlayInstallResult]) {
        defer { cleanupTransientInstallFiles() }
        let installationLock = try InstallationLock(at: paths.applicationSupportDirectory.appending(path: "RuntimeInstallation.lock"))
        defer { withExtendedLifetime(installationLock) {} }
        guard archives.runtimeReleases.wine.versionTag == "11.16" else {
            throw RuntimeInstallerError.installFailed("This Wine build requires a newer Scotch with matching graphics support.")
        }
        try ensureDiskSpace(requiredBytes: 2_500_000_000)

        try fileSystem.createDirectory(at: paths.applicationSupportDirectory)

        let libraries = paths.librariesDirectory
        let backupURL = paths.applicationSupportDirectory
            .appending(path: "Libraries.backup-\(UUID().uuidString)")
        let hadExistingInstall = fileSystem.fileExists(at: libraries)

        if hadExistingInstall {
            try fileSystem.moveItem(at: libraries, to: backupURL)
        }

        do {
            try fileSystem.createDirectory(at: libraries)
            try await installWine(from: archives.wineArchive)
            try await installMetalEngine()
            try await installTranslationLibrary(componentName: "DXVK", archive: archives.dxvkArchive, destination: libraries.appending(path: "DXVK"))
            try await installTranslationLibrary(componentName: "DXMT", archive: archives.dxmtArchive, destination: libraries.appending(path: "DXMT"))

            try await installGraphicsSupport()

            let overlayResults = try await [
                installOverlay(component: .winemacOpenGLPatch),
                installOptionalD3DMetal(previousLibraries: hadExistingInstall ? backupURL : nil),
                installOverlay(component: .zink)
            ]

            try await installGPUSpoofShim()

            let manifest = RuntimeManifest(
                runtimeSetID: approvedRuntime?.id,
                wineVersion: archives.runtimeReleases.wine.versionTag,
                dxvkVersion: archives.runtimeReleases.dxvk.versionTag,
                dxmtVersion: archives.runtimeReleases.dxmt.versionTag,
                d3dmetalVersion: overlayResults.first(where: { $0.component == .d3dmetal })?.installedVersion,
                winemacPatchVersion: overlayResults.first(where: { $0.component == .winemacOpenGLPatch })?.installedVersion,
                zinkVersion: overlayResults.first(where: { $0.component == .zink })?.installedVersion
            )

            try validateManifest(manifest)
            try verifyInstalledArtifacts()
            try MetalEngineInstallation.verify(in: libraries)
            try MetalEngineInstallation.verifyDXMT(in: libraries)
            try GraphicsSupportInstallation.verify(in: libraries)
            await stripQuarantine(at: libraries)

            try await WineBundleSigning(processRunner: processRunner).verify(at: paths.wineBundleURL)

            try await plistStore.write(manifest, to: paths.runtimeManifestURL)
            if hadExistingInstall, fileSystem.fileExists(at: backupURL) {
                try? fileSystem.removeItem(at: backupURL)
            }
            cleanupTransientInstallFiles()
            return (manifest, overlayResults)
        } catch {
            if fileSystem.fileExists(at: libraries) {
                try? fileSystem.removeItem(at: libraries)
            }
            if hadExistingInstall, fileSystem.fileExists(at: backupURL) {
                try? fileSystem.moveItem(at: backupURL, to: libraries)
            }
            cleanupTransientInstallFiles()
            throw error
        }
    }

    public func shouldUpdateRuntime() async -> (Bool, AppVersion) {
        guard let manifest = await currentManifest() else {
            return (false, AppVersion(0, 0, 0))
        }
        let expectedWine = (approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag)
        let expectedDXVK = approvedRuntime?.package(.dxvk)?.version ?? RuntimeAssets.dxvk.versionTag
        let expectedDXMT = approvedRuntime?.package(.dxmt)?.version ?? RuntimeAssets.dxmt.versionTag
        let expectedVersion = AppVersion(parsing: expectedWine) ?? AppVersion(0, 0, 0)
        return (
            manifest.wineVersion != expectedWine ||
                manifest.dxvkVersion != expectedDXVK ||
                manifest.dxmtVersion != expectedDXMT,
            expectedVersion
        )
    }

    public func overlayDrifts() async -> [OverlayDrift] {
        guard let manifest = await currentManifest() else {
            return []
        }

        var drifts: [OverlayDrift] = []
        if manifest.winemacPatchVersion != ("stock-" + (approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag)) {
            drifts.append(OverlayDrift(component: .winemacOpenGLPatch, installedVersion: manifest.winemacPatchVersion, expectedVersion: ("stock-" + (approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag))))
        }
        if let installed = manifest.d3dmetalVersion, installed != OverlayVersion.d3dmetal {
            drifts.append(OverlayDrift(component: .d3dmetal, installedVersion: manifest.d3dmetalVersion, expectedVersion: OverlayVersion.d3dmetal))
        }
        if manifest.zinkVersion != (approvedRuntime.map { "mesa-" + ($0.package(.zink)?.version ?? "unknown") } ?? OverlayVersion.zink) {
            drifts.append(OverlayDrift(component: .zink, installedVersion: manifest.zinkVersion, expectedVersion: (approvedRuntime.map { "mesa-" + ($0.package(.zink)?.version ?? "unknown") } ?? OverlayVersion.zink)))
        }
        return drifts
    }

    private func downloadAsset(
        _ asset: ReleaseAsset,
        into directory: URL,
        reportBytes: @Sendable @escaping (Int64) -> Void
    ) async throws -> URL {
        guard asset.name == URL(fileURLWithPath: asset.name).lastPathComponent, !asset.name.hasPrefix(".") else {
            throw RuntimeInstallerError.downloadFailed("Invalid asset filename")
        }
        let destination = directory.appending(path: asset.name)
        let cacheDir = RuntimeDownloadCache(paths: paths).directory
        let cache = asset.sha256.map { cacheDir.appending(path: $0.lowercased()) }
        if let cache, fileSystem.fileExists(at: cache), let expected = asset.sha256,
           (try? SHA256Checksum.hashFile(at: cache)) == expected.lowercased() {
            if fileSystem.fileExists(at: destination) { try fileSystem.removeItem(at: destination) }
            // Another process may clear the cache. A cache miss must not break setup.
            if (try? fileSystem.copyItem(at: cache, to: destination)) != nil {
                reportBytes(asset.size)
                return destination
            }
        }
        do {
            let temporaryFile = try await networkClient.download(from: NetworkRequest(url: asset.downloadURL))
            if fileSystem.fileExists(at: destination) {
                try fileSystem.removeItem(at: destination)
            }
            try fileSystem.moveItem(at: temporaryFile, to: destination)
            if asset.size > 0 {
                let bytes = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard Int64(bytes) == asset.size else { throw RuntimeInstallerError.downloadFailed("Unexpected file size for \(asset.name)") }
            }
            if let expectedChecksum = asset.sha256 {
                try verifyChecksum(expectedChecksum, for: destination, assetName: asset.name)
            }
            let contentCache = try cache ?? cacheDir.appending(path: SHA256Checksum.hashFile(at: destination))
            try fileSystem.createDirectory(at: cacheDir)
            let staged = cacheDir.appending(path: ".partial-" + UUID().uuidString)
            defer { try? fileSystem.removeItem(at: staged) }
            try fileSystem.copyItem(at: destination, to: staged)
            guard rename(staged.path, contentCache.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            reportBytes(asset.size)
            return destination
        } catch let NetworkClientError.nonSuccessStatus(_, status) {
            throw RuntimeInstallerError.downloadFailed("\(asset.name) HTTP \(status)")
        } catch let networkError as NetworkClientError {
            throw RuntimeInstallerError.downloadFailed("\(asset.name): \(networkError.errorDescription ?? "unknown")")
        } catch let runtimeError as RuntimeInstallerError {
            throw runtimeError
        } catch {
            throw RuntimeInstallerError.downloadFailed("\(asset.name): \(error.localizedDescription)")
        }
    }

    private func installWine(from archive: URL) async throws {
        let scratch = scratchRoot.appending(path: "wine")
        if fileSystem.fileExists(at: scratch) {
            try fileSystem.removeItem(at: scratch)
        }
        try fileSystem.createDirectory(at: scratch)
        try await TarArchive.extract(archive, to: scratch, using: processRunner)

        guard let wineRoot = locateWineRoot(in: scratch) else {
            throw RuntimeInstallerError.extractionFailed("Unable to locate wine root in archive")
        }

        let destination = paths.librariesDirectory.appending(path: "Wine")
        if fileSystem.fileExists(at: destination) {
            try fileSystem.removeItem(at: destination)
        }
        try fileSystem.moveItem(at: wineRoot, to: destination)
        try? fileSystem.removeItem(at: scratch)

        try createWineAppBundle()
        try await WineBundleSigning(processRunner: processRunner).signAndVerify(at: paths.wineBundleURL)
    }

    private func locateWineRoot(in directory: URL) -> URL? {
        let enumerator = fileSystem.enumerator(at: directory)
        while let item = enumerator?.nextObject() as? URL {
            let name = item.lastPathComponent
            if name == "wine" || name == "wine64" {
                let bin = item.deletingLastPathComponent()
                if bin.lastPathComponent == "bin" {
                    return bin.deletingLastPathComponent()
                }
            }
        }
        return nil
    }

    private func installTranslationLibrary(componentName: String, archive: URL, destination: URL) async throws {
        let scratch = scratchRoot.appending(path: componentName.lowercased())
        if fileSystem.fileExists(at: scratch) {
            try fileSystem.removeItem(at: scratch)
        }
        try fileSystem.createDirectory(at: scratch)
        try await TarArchive.extract(archive, to: scratch, using: processRunner)

        let x64Candidates = Set(["x64", "x86_64-windows"])
        let x32Candidates = Set(["x32", "i386-windows"])
        let unixCandidates = Set(["x86_64-unix", "i386-unix"])

        var x64Dir: URL?
        var x32Dir: URL?
        var unixDirs: [URL] = []

        let enumerator = fileSystem.enumerator(at: scratch)
        while let item = enumerator?.nextObject() as? URL {
            let name = item.lastPathComponent
            if x64Dir == nil && x64Candidates.contains(name) {
                x64Dir = item
            }
            if x32Dir == nil && x32Candidates.contains(name) {
                x32Dir = item
            }
            if unixCandidates.contains(name) {
                unixDirs.append(item)
            }
        }

        guard let x64Dir, let x32Dir else {
            throw RuntimeInstallerError.extractionFailed("\(componentName) archive missing x64/x32 trees")
        }

        if fileSystem.fileExists(at: destination) {
            try fileSystem.removeItem(at: destination)
        }
        try fileSystem.createDirectory(at: destination)
        try fileSystem.moveItem(at: x64Dir, to: destination.appending(path: componentName == "DXMT" ? "x86_64-windows" : "x64"))
        try fileSystem.moveItem(at: x32Dir, to: destination.appending(path: componentName == "DXMT" ? "i386-windows" : "x32"))

        let componentRoot = x64Dir.deletingLastPathComponent()
        for notice in (try? fileSystem.contentsOfDirectory(at: componentRoot)) ?? [] {
            let name = notice.lastPathComponent.uppercased()
            if name.hasPrefix("LICENSE") || name.hasPrefix("COPYING") || name.hasPrefix("README") || name == "AUTHORS" {
                try fileSystem.copyItem(at: notice, to: destination.appending(path: notice.lastPathComponent))
            }
        }
        if componentName == "DXMT" {
            for unix in unixDirs {
                try fileSystem.copyItem(at: unix, to: destination.appending(path: unix.lastPathComponent))
            }
            try FileManager.default.createSymbolicLink(atPath: destination.appending(path: "x64").path, withDestinationPath: "x86_64-windows")
            try FileManager.default.createSymbolicLink(atPath: destination.appending(path: "x32").path, withDestinationPath: "i386-windows")
        } else {
            for unix in unixDirs { try mergeWineExtension(from: unix) }
        }

        try? fileSystem.removeItem(at: scratch)
    }

    private func mergeWineExtension(from source: URL) throws {
        let targetDirectory = paths.librariesDirectory
            .appending(path: "Wine/lib/wine")
            .appending(path: source.lastPathComponent)

        guard fileSystem.fileExists(at: targetDirectory) else {
            logger.info("Skipped unix extension merge for \(source.lastPathComponent): target missing")
            return
        }

        let files = (try? fileSystem.contentsOfDirectory(at: source)) ?? []
        for file in files {
            let target = targetDirectory.appending(path: file.lastPathComponent)
            if fileSystem.fileExists(at: target) {
                try fileSystem.removeItem(at: target)
            }
            try fileSystem.copyItem(at: file, to: target)
        }
    }

    private func createWineAppBundle(at bundleURL: URL? = nil, engineDirectory: String = "Wine") throws {
        let bundleURL = bundleURL ?? paths.wineBundleURL
        let contents = bundleURL.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")

        if fileSystem.fileExists(at: bundleURL) {
            try fileSystem.removeItem(at: bundleURL)
        }
        try fileSystem.createDirectory(at: macOS)

        let launcherURL = macOS.appending(path: "wine-launcher")
        try wineLauncherScript(engineDirectory: engineDirectory).write(to: launcherURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path(percentEncoded: false))
        try wineInfoPlist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }

    private func installOverlay(component: OverlayComponent) async throws -> OverlayInstallResult {
        if component == .winemacOpenGLPatch {
            try verifyOverlayInstall(component: .winemacOpenGLPatch)
            logger.info("Using stock winemac.so from Wine \((approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag))")
            return OverlayInstallResult(
                component: component,
                installedVersion: ("stock-" + (approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag)),
                errorMessage: nil
            )
        }

        if component == .zink {
            try await installZink()
            try verifyOverlayInstall(component: .zink)
            logger.info("Installed Mesa Zink \(RuntimeAssets.zink.versionTag)")
            return OverlayInstallResult(component: .zink, installedVersion: (approvedRuntime.map { "mesa-" + ($0.package(.zink)?.version ?? "unknown") } ?? OverlayVersion.zink), errorMessage: nil)
        }

        try await installD3DMetal()
        try verifyOverlayInstall(component: component)
        logger.info("Installed overlay \(component.displayName) version \(OverlayVersion.d3dmetal)")
        return OverlayInstallResult(component: component, installedVersion: approvedRuntime?.package(.d3dmetal)?.version ?? OverlayVersion.d3dmetal, errorMessage: nil)
    }

    public func needsGraphicsRepair() async -> Bool {
        guard paths.runtimeDirectoryOverride == nil,
              let manifest = try? await plistStore.read(RuntimeManifest.self, from: paths.runtimeManifestURL),
              manifest.wineVersion == "11.16" else { return false }
        do {
            try MetalEngineInstallation.verify(in: paths.librariesDirectory)
            try MetalEngineInstallation.verifyDXMT(in: paths.librariesDirectory)
            try GraphicsSupportInstallation.verify(in: paths.librariesDirectory)
            try D3DMetalInstallation.verify(at: paths.librariesDirectory.appending(path: "D3DMetal"))
            try verifyOverlayInstall(component: .zink)
            for arch in ["x64", "x32"] {
                for name in ["d3d10core", "d3d11"] {
                    try PackageArchitecture.verifyPE(at: paths.librariesDirectory.appending(path: "DXVK/\(arch)/\(name).dll"), machine: arch == "x64" ? 0x8664 : 0x014c)
                }
            }
            guard manifest.dxvkVersion == RuntimeAssets.dxvk.versionTag, manifest.dxmtVersion == RuntimeAssets.dxmt.versionTag,
                  manifest.zinkVersion == OverlayVersion.zink,
                  (try? String(contentsOf: paths.librariesDirectory.appending(path: "MetalEngine/Wine.app/Contents/MacOS/wine-launcher"), encoding: .utf8)) == wineLauncherScript(engineDirectory: "Engine"),
                  (try? SHA256Checksum.hashFile(at: paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so"))) == RuntimeAssets.stockMacDriverSHA256 else { return true }
            return false
        } catch { return true }
    }

    /// Stage a complete copy and exchange the runtime directory atomically. No
    /// prefix is opened; a failure leaves every previously installed file active.
    public func repairGraphics() async throws {
        let lease = try UpdateActivity.shared.acquireMaintenance()
        defer { withExtendedLifetime(lease) {}; cleanupTransientInstallFiles() }
        let lock = try InstallationLock(at: paths.applicationSupportDirectory.appending(path: "RuntimeInstallation.lock"))
        defer { withExtendedLifetime(lock) {} }
        guard paths.runtimeDirectoryOverride == nil,
              var manifest = try? await plistStore.read(RuntimeManifest.self, from: paths.runtimeManifestURL),
              manifest.wineVersion == "11.16" else {
            throw RuntimeInstallerError.installFailed("Install the core Wine 11.16 runtime before repairing graphics support.")
        }
        try ensureDiskSpace(requiredBytes: 3_000_000_000)
        var stagedPaths = paths
        stagedPaths.runtimeDirectoryOverride = scratchRoot.appending(path: "repaired-libraries")
        try fileSystem.createDirectory(at: stagedPaths.librariesDirectory.deletingLastPathComponent())
        try fileSystem.copyItem(at: paths.librariesDirectory, to: stagedPaths.librariesDirectory)
        let installer = RuntimeInstallerService(paths: stagedPaths, fileSystem: fileSystem, logger: logger,
            plistStore: plistStore, processRunner: processRunner, networkClient: networkClient)
        try await installer.installGraphicsForRepair()
        manifest.d3dmetalVersion = D3DMetalInstallation.version
        manifest.dxmtVersion = RuntimeAssets.dxmt.versionTag
        manifest.dxvkVersion = RuntimeAssets.dxvk.versionTag
        manifest.zinkVersion = OverlayVersion.zink
        manifest.winemacPatchVersion = OverlayVersion.winemac
        try await plistStore.write(manifest, to: stagedPaths.runtimeManifestURL)
        await stripQuarantine(at: stagedPaths.librariesDirectory)
        try Task.checkCancellation()
        guard !UpdateActivity.shared.hasRunningWineProcesses else {
            throw RuntimeInstallerError.installFailed("Close Wine processes before activating the graphics repair.")
        }
        guard renamex_np(stagedPaths.librariesDirectory.path, paths.librariesDirectory.path, UInt32(RENAME_SWAP)) == 0 else {
            throw RuntimeInstallerError.installFailed("Unable to activate graphics support. The previous runtime is unchanged.")
        }
    }

    private func installGraphicsForRepair() async throws {
        defer { cleanupTransientInstallFiles() }
        try await restoreStockMacDriverIfNeeded()
        try await installMetalEngine()
        let dxvk = try await downloadAsset(RuntimeAssets.dxvk, into: scratchRoot) { _ in }
        try await installTranslationLibrary(componentName: "DXVK", archive: dxvk, destination: paths.librariesDirectory.appending(path: "DXVK"))
        let archive = try await downloadAsset(RuntimeAssets.dxmt, into: scratchRoot) { _ in }
        try await installTranslationLibrary(componentName: "DXMT", archive: archive, destination: paths.librariesDirectory.appending(path: "DXMT"))
        try await installGraphicsSupport()
        try await installZink()
        try await installD3DMetal()
        try MetalEngineInstallation.verify(in: paths.librariesDirectory)
        try MetalEngineInstallation.verifyDXMT(in: paths.librariesDirectory)
        try GraphicsSupportInstallation.verify(in: paths.librariesDirectory)
        try D3DMetalInstallation.verify(at: paths.librariesDirectory.appending(path: "D3DMetal"))
        try verifyInstalledArtifacts()
    }

    private func restoreStockMacDriverIfNeeded() async throws {
        let target = paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so")
        guard (try? SHA256Checksum.hashFile(at: target)) != RuntimeAssets.stockMacDriverSHA256 else { return }
        let scratch = scratchRoot.appending(path: "stock-mac-driver")
        try fileSystem.createDirectory(at: scratch)
        let archive = try await downloadAsset(RuntimeAssets.wine, into: scratch) { _ in }
        try await TarArchive.extract(archive, to: scratch, using: processRunner, members: [RuntimeAssets.stockMacDriverMember])
        let source = scratch.appending(path: RuntimeAssets.stockMacDriverMember)
        guard try SHA256Checksum.hashFile(at: source) == RuntimeAssets.stockMacDriverSHA256 else {
            throw RuntimeInstallerError.installFailed("The stock Wine Mac driver failed verification.")
        }
        if fileSystem.fileExists(at: target) { try fileSystem.removeItem(at: target) }
        try fileSystem.copyItem(at: source, to: target)
    }

    private func installGraphicsSupport() async throws {
        guard let archive = RuntimeResources.bundled.url(forResource: "GraphicsSupport", withExtension: "tar.xz"),
              try SHA256Checksum.hashFile(at: archive) == GraphicsSupportInstallation.archiveSHA256 else {
            throw RuntimeInstallerError.installFailed("The app's graphics support is missing or damaged. Reinstall Scotch.")
        }
        let scratch = scratchRoot.appending(path: "graphics-support")
        try fileSystem.createDirectory(at: scratch)
        try await TarArchive.extract(archive, to: scratch, using: processRunner)
        try GraphicsSupportInstallation.verify(in: scratch)
        for member in GraphicsSupportInstallation.files.keys {
            let source = scratch.appending(path: member)
            let target = paths.librariesDirectory.appending(path: member)
            try fileSystem.createDirectory(at: target.deletingLastPathComponent())
            guard target.deletingLastPathComponent().resolvingSymlinksInPath().path.hasPrefix(paths.librariesDirectory.resolvingSymlinksInPath().path + "/") else {
                throw RuntimeInstallerError.installFailed("Unexpected graphics directory layout. The previous runtime is unchanged.")
            }
            if fileSystem.fileExists(at: target) || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil { try fileSystem.removeItem(at: target) }
            try fileSystem.copyItem(at: source, to: target)
        }
        try GraphicsSupportInstallation.verify(in: paths.librariesDirectory)
    }

    private func installMetalEngine() async throws {
        try ensureDiskSpace(requiredBytes: 1_500_000_000)
        let scratch = scratchRoot.appending(path: "metal-engine")
        try fileSystem.createDirectory(at: scratch)
        let engineImage = try await downloadAsset(MetalEngineInstallation.asset, into: scratch) { _ in }
        let destination = paths.librariesDirectory.appending(path: "MetalEngine")
        if fileSystem.fileExists(at: destination) { try fileSystem.removeItem(at: destination) }
        try fileSystem.createDirectory(at: destination)
        // Copy only the matching Wine engine and its licenses, never the other
        // application's launcher or user data. Mount only our unique temp path.
        let mount = scratch.appending(path: "mount")
        try fileSystem.createDirectory(at: mount)
        _ = try await processRunner.captureProcess(ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, "-plist", engineImage.path],
            displayName: "Mount compatible Metal engine", timeout: 60), outputFileHandle: nil)
        let detach = ProcessSpecification(executableURL: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["detach", mount.path], displayName: "Eject matched engine image", timeout: 30)
        do {
            let resources = mount.appending(path: "WineForge.app/Contents/Resources")
            let engine = destination.appending(path: "Engine")
            try fileSystem.createDirectory(at: engine)
            for item in try fileSystem.contentsOfDirectory(at: resources.appending(path: "Engine/WineForgeCore")) where item.lastPathComponent != "include" {
                try fileSystem.copyItem(at: item, to: engine.appending(path: item.lastPathComponent))
            }
            try fileSystem.copyItem(at: resources.appending(path: "Licenses"), to: destination.appending(path: "Licenses"))
            // WineForge's engine omits Mono/Gecko. Without the matching shared
            // packages, its first prefix update can open an installer and block
            // registry commands indefinitely. Reuse the packages supplied by
            // our pinned core Wine instead of disabling .NET or MSHTML in games.
            for component in ["mono", "gecko"] {
                try fileSystem.copyItem(at: paths.librariesDirectory.appending(path: "Wine/share/wine/" + component),
                    to: destination.appending(path: "Engine/share/wine/" + component))
            }
            _ = try await processRunner.captureProcess(detach, outputFileHandle: nil)
        } catch {
            _ = try? await processRunner.captureProcess(detach, outputFileHandle: nil)
            throw error
        }
        let bundle = destination.appending(path: "Wine.app")
        try createWineAppBundle(at: bundle, engineDirectory: "Engine")
        try await WineBundleSigning(processRunner: processRunner).signAndVerify(at: bundle)
        let output = try await processRunner.captureProcess(ProcessSpecification(
            executableURL: destination.appending(path: "Engine/bin/wine"), arguments: ["--version"],
            environment: ["WINEPREFIX": scratch.appending(path: "probe-prefix").path,
                          "DYLD_LIBRARY_PATH": destination.appending(path: "Engine/lib").path],
            displayName: "Verify matched Wine 11.16", timeout: 30), outputFileHandle: nil)
        guard output.contains("wine-11.16") else { throw RuntimeInstallerError.installFailed("D3DMetal engine version does not match Wine 11.16") }
        try MetalEngineInstallation.version.write(to: destination.appending(path: "EngineVersion"), atomically: true, encoding: .utf8)
        try MetalEngineInstallation.verify(in: paths.librariesDirectory)
        try "WineForge source: https://github.com/Alien4042x/WineForge/tree/0.6.0.3\nOriginal licenses: Licenses/\nScotch build instructions and corresponding source: the Sources folder in the Scotch disk image.\n".write(to: destination.appending(path: "Sources.txt"), atomically: true, encoding: .utf8)
    }

    private func installD3DMetal(into libraries: URL? = nil) async throws {
        let package = approvedRuntime?.package(.d3dmetal)
        guard package == nil || package?.layoutVersion == 3 else {
            throw RuntimeInstallerError.installFailed("D3DMetal requires GPTK layout 3 and the compatible Metal engine.")
        }
        let scratch = scratchRoot.appending(path: "d3dmetal")
        try fileSystem.createDirectory(at: scratch)
        let archive = try await downloadAsset(package?.asset ?? D3DMetalInstallation.toolkit, into: scratch) { _ in }
        let source = scratch.appending(path: D3DMetalInstallation.toolkitLibraryPath)
        let members = ["external/D3DMetal.framework", "external/libd3dshared.dylib"]
            + D3DMetalInstallation.modules.flatMap { ["wine/x86_64-windows/\($0).dll", "wine/x86_64-unix/\($0).so"] }
        try await TarArchive.extract(archive, to: scratch, using: processRunner,
            members: members.map { D3DMetalInstallation.toolkitLibraryPath + "/" + $0 })
        let destination = (libraries ?? paths.librariesDirectory).appending(path: "D3DMetal")
        if fileSystem.fileExists(at: destination) { try fileSystem.removeItem(at: destination) }
        try fileSystem.moveItem(at: source, to: destination)
        _ = try await processRunner.captureProcess(ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", destination.appending(path: "external/D3DMetal.framework").path],
            displayName: "Verify D3DMetal framework", timeout: 30), outputFileHandle: nil)
        try "D3DMetal 3.0: \(D3DMetalInstallation.toolkit.downloadURL)\nOriginal notices: external/D3DMetal.framework/Resources/\n".write(to: destination.appending(path: "Sources.txt"), atomically: true, encoding: .utf8)
    }

    private func installOptionalD3DMetal(previousLibraries: URL?) async throws -> OverlayInstallResult {
        if let approvedRuntime, approvedRuntime.package(.d3dmetal) == nil {
            return OverlayInstallResult(component: .d3dmetal, installedVersion: nil, errorMessage: nil)
        }
        do {
            return try await installOverlay(component: .d3dmetal)
        } catch {
            try Task.checkCancellation()
            // A signed set that includes D3DMetal must be complete before it
            // can be activated. Optional fallback applies only to bootstrap.
            if approvedRuntime?.package(.d3dmetal) != nil { throw error }
            let message = error.localizedDescription
            let destination = paths.librariesDirectory.appending(path: "D3DMetal")
            // Never advertise a partially extracted backend as available.
            if fileSystem.fileExists(at: destination) {
                try fileSystem.removeItem(at: destination)
            }

            // A missing download must not discard a working backend during reinstall.
            if let previousLibraries,
               let previousManifest = try? await plistStore.read(RuntimeManifest.self, from: previousLibraries.appending(path: RuntimeManifest.fileName)),
               let version = previousManifest.d3dmetalVersion, !version.isEmpty,
               fileSystem.fileExists(at: previousLibraries.appending(path: "D3DMetal")) {
                do {
                    try fileSystem.copyItem(at: previousLibraries.appending(path: "D3DMetal"), to: destination)
                    try verifyOverlayInstall(component: .d3dmetal)
                    logger.warning("D3DMetal download failed; keeping installed \(version): \(message)")
                    return OverlayInstallResult(component: .d3dmetal, installedVersion: version, errorMessage: "Kept existing D3DMetal. \(message)")
                } catch {
                    if fileSystem.fileExists(at: destination) {
                        try fileSystem.removeItem(at: destination)
                    }
                }
            }

            logger.warning("Continuing without optional D3DMetal: \(message)")
            return OverlayInstallResult(component: .d3dmetal, installedVersion: nil, errorMessage: message)
        }
    }

    private func installZink() async throws {
        let scratch = scratchRoot.appending(path: "zink")
        if fileSystem.fileExists(at: scratch) {
            try fileSystem.removeItem(at: scratch)
        }
        try fileSystem.createDirectory(at: scratch)
        defer { try? fileSystem.removeItem(at: scratch) }

        let archive = try await downloadAsset(approvedRuntime?.package(.zink)?.asset ?? RuntimeAssets.zink, into: scratch) { _ in }
        // macOS tar (libarchive) supports upstream's 7z format.
        try await TarArchive.extract(archive, to: scratch, using: processRunner)

        for (sourceArchitecture, destinationArchitecture) in [("x64", "x64"), ("x86", "x32")] {
            let destination = paths.librariesDirectory.appending(path: "Zink/\(destinationArchitecture)")
            if fileSystem.fileExists(at: destination) { try fileSystem.removeItem(at: destination) }
            try fileSystem.createDirectory(at: destination)
            // Include the Gallium dependency, but not Mesa's unrelated D3D/Vulkan drivers.
            for name in ["opengl32.dll", "libgallium_wgl.dll", "libEGL.dll", "libGLESv1_CM.dll", "libGLESv2.dll"] {
                let source = scratch.appending(path: "\(sourceArchitecture)/\(name)")
                guard fileSystem.fileExists(at: source) else {
                    throw RuntimeInstallerError.extractionFailed("Mesa Zink archive missing \(sourceArchitecture)/\(name)")
                }
                try fileSystem.copyItem(at: source, to: destination.appending(path: name))
            }
        }
    }

    private func verifyOverlayInstall(component: OverlayComponent) throws {
        switch component {
        case .winemacOpenGLPatch:
            let winemac = paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so")
            guard fileSystem.fileExists(at: winemac) else {
                throw RuntimeInstallerError.installFailed("winemac verification failed: winemac.so missing from Wine \((approvedRuntime?.package(.wine)?.version ?? RuntimeAssets.wine.versionTag))")
            }
        case .d3dmetal:
            try D3DMetalInstallation.verify(at: paths.librariesDirectory.appending(path: "D3DMetal"))
        case .zink:
            for architecture in ["x64", "x32"] {
                for name in ["opengl32.dll", "libgallium_wgl.dll"] {
                    let marker = paths.librariesDirectory.appending(path: "Zink/\(architecture)/\(name)")
                    guard fileSystem.fileExists(at: marker) else {
                        throw RuntimeInstallerError.installFailed("Zink overlay verification failed: \(architecture)/\(name) missing")
                    }
                }
            }
        }
    }

    private func verifyChecksum(_ expected: String, for fileURL: URL, assetName: String) throws {
        guard let normalizedExpected = normalizeHash(expected) else {
            logger.warning("Ignoring invalid checksum format for \(assetName)")
            return
        }

        let actual = try SHA256Checksum.hashFile(at: fileURL)
        if actual != normalizedExpected {
            try? fileSystem.removeItem(at: fileURL)
            throw RuntimeInstallerError.downloadFailed(
                "Checksum mismatch for \(assetName): expected \(normalizedExpected), got \(actual)"
            )
        }
    }

    private func normalizeHash(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter(\.isHexDigit)
        guard normalized.count == 64 else {
            return nil
        }
        return normalized
    }

    private func installGPUSpoofShim() async throws {
        let sourceURL = RuntimeResources.bundled.url(
            forResource: "libscotch_gpu_spoof", withExtension: "dylib", subdirectory: "VulkanSpoof"
        )

        guard let sourceURL else {
            throw RuntimeInstallerError.installFailed("GPU spoof shim dylib not bundled in runtime resources")
        }

        let spoofDirectory = paths.librariesDirectory.appending(path: "VulkanSpoof")
        if !fileSystem.fileExists(at: spoofDirectory) {
            try fileSystem.createDirectory(at: spoofDirectory)
        }

        let outputURL = spoofDirectory.appending(path: "libscotch_gpu_spoof.dylib")
        if fileSystem.fileExists(at: outputURL) {
            try fileSystem.removeItem(at: outputURL)
        }

        try fileSystem.copyItem(at: sourceURL, to: outputURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outputURL.path(percentEncoded: false))
    }

    private func wineLauncherScript(engineDirectory: String) -> String {
        """
        #!/bin/bash
        HERE="$(cd "$(dirname "$0")" && pwd)"
        LIBS="$(cd "$HERE/../../.." && pwd)"
        if [ -n "${SCOTCH_LAUNCH_ENV:-}" ] && [ -f "$SCOTCH_LAUNCH_ENV" ]; then
          set -a
          # shellcheck disable=SC1090
          . "$SCOTCH_LAUNCH_ENV"
          set +a
        fi
        if [ -n "${SCOTCH_LAUNCH_CWD:-}" ]; then
          cd -- "$SCOTCH_LAUNCH_CWD" || exit 1
        fi
        if [ -n "${SCOTCH_GPU_SPOOF_LIB:-}" ] && [ -f "$SCOTCH_GPU_SPOOF_LIB" ]; then
          export CX_LIBVULKAN="$SCOTCH_GPU_SPOOF_LIB"
          export SCOTCH_REAL_MOLTENVK_PATH="${SCOTCH_REAL_MOLTENVK_PATH:-$LIBS/\(engineDirectory)/lib/libMoltenVK.dylib}"
          export DYLD_LIBRARY_PATH="$(dirname "$SCOTCH_GPU_SPOOF_LIB")${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        fi
        export PATH="$LIBS/\(engineDirectory)/bin:${PATH:-/usr/bin:/bin}"
        export WINE="${WINE:-$LIBS/\(engineDirectory)/bin/wine}"
        exec "$LIBS/\(engineDirectory)/bin/wine" "$@"
        """
    }

    private func stripQuarantine(at url: URL) async {
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", url.path(percentEncoded: false)],
            displayName: "xattr -d quarantine",
            timeout: 60
        )
        _ = try? await processRunner.captureProcess(spec, outputFileHandle: nil)
    }

    private func cleanupTransientInstallFiles() {
        let transients = [
            downloadsRoot,
            scratchRoot
        ]
        for url in transients where fileSystem.fileExists(at: url) {
            try? fileSystem.removeItem(at: url)
        }
    }

    private var wineInfoPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key><string>wine-launcher</string>
            <key>CFBundleIdentifier</key><string>com.s3brr.Scotch.WineBundle</string>
            <key>CFBundleName</key><string>Wine</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>LSMinimumSystemVersion</key><string>26.0</string>
            <key>NSPrincipalClass</key><string>NSApplication</string>
            <key>LSUIElement</key><false/>
            <key>LSBackgroundOnly</key><false/>
        </dict>
        </plist>
        """
    }

    private func ensureDiskSpace(requiredBytes: Int64) throws {
        let targetDirectory = paths.applicationSupportDirectory.deletingLastPathComponent()
        let values = try? targetDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let available = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let minimumRequired = max(requiredBytes * 2, 1_000_000_000)

        if available < minimumRequired {
            throw RuntimeInstallerError.installFailed(
                "Insufficient disk space: required at least \(minimumRequired / (1024 * 1024)) MB, available \(available / (1024 * 1024)) MB"
            )
        }
    }

    private func verifyInstalledArtifacts() throws {
        let requiredPaths = [
            paths.wineBinaryURL,
            paths.wineBundleURL,
            paths.librariesDirectory.appending(path: "DXVK"),
            paths.librariesDirectory.appending(path: "DXMT"),
            paths.librariesDirectory.appending(path: "VulkanSpoof/libscotch_gpu_spoof.dylib")
        ]

        for path in requiredPaths where !fileSystem.fileExists(at: path) {
            throw RuntimeInstallerError.installFailed("Post-install verification failed: missing \(path.path(percentEncoded: false))")
        }

        try verifyOverlayInstall(component: .winemacOpenGLPatch)
        try verifyOverlayInstall(component: .zink)
        if approvedRuntime != nil {
            try MetalEngineInstallation.verify(in: paths.librariesDirectory)
            try MetalEngineInstallation.verifyDXMT(in: paths.librariesDirectory)
            try GraphicsSupportInstallation.verify(in: paths.librariesDirectory)
            for component in ["DXVK", "Zink"] {
                try PackageArchitecture.windowsDLLs(in: paths.librariesDirectory.appending(path: component + "/x64"), machine: 0x8664)
                try PackageArchitecture.windowsDLLs(in: paths.librariesDirectory.appending(path: component + "/x32"), machine: 0x014c)
            }
        }
    }

    private func validateManifest(_ manifest: RuntimeManifest) throws {
        if manifest.wineVersion.isEmpty || manifest.dxvkVersion.isEmpty || manifest.dxmtVersion.isEmpty {
            throw RuntimeInstallerError.installFailed("Manifest sanity check failed: missing core runtime versions")
        }
        let overlays = [
            manifest.winemacPatchVersion,
            manifest.zinkVersion
        ]
        if overlays.contains(where: { ($0 ?? "").isEmpty }) {
            throw RuntimeInstallerError.installFailed("Manifest sanity check failed: missing required overlay versions")
        }
    }
}

private final class DownloadProgressCounter: @unchecked Sendable {
    private var completed: Int64 = 0
    private let total: Int64
    private let lock = NSLock()

    init(total: Int64) {
        self.total = total
    }

    func advance(by bytes: Int64) -> Double {
        lock.lock()
        completed += bytes
        let snapshot = completed
        lock.unlock()
        return Double(snapshot) / Double(total)
    }
}
