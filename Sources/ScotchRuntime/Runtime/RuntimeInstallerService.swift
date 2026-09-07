import Foundation
import ScotchDomain
import ScotchInfrastructure

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    let tagName: String
    let draft: Bool?
    let prerelease: Bool?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

private struct RuntimeAssetRequirement: Sendable {
    let displayName: String
    let repo: String
    let versionTag: String
    let assetNamePatterns: [String]
}

public actor RuntimeInstallerService: RuntimeInstallerProtocol {
    private enum OverlayVersion {
        static let winemac = "wine-openglpatch-11.6"
        static let d3dmetal = "d3dmetal-3.0"
        static let zink = "zink-1.0"
    }

    private enum RuntimeMatrix {
        static let wine = RuntimeAssetRequirement(
            displayName: "Wine",
            repo: "Gcenx/macOS_Wine_builds",
            versionTag: "11.6_1",
            assetNamePatterns: ["wine-staging-", "-osx64"]
        )
        static let dxvk = RuntimeAssetRequirement(
            displayName: "DXVK",
            repo: "Gcenx/DXVK-macOS",
            versionTag: "v1.10.3-20230507-repack",
            assetNamePatterns: ["dxvk-macOS-async", "-repack.tar"]
        )
        static let dxmt = RuntimeAssetRequirement(
            displayName: "DXMT",
            repo: "3Shain/dxmt",
            versionTag: "v0.80",
            assetNamePatterns: ["dxmt-", "builtin.tar"]
        )
    }

    private let paths: AppPaths
    private let fileSystem: LocalFileSystem
    private let logger: AppLogger
    private let plistStore: PlistStore
    private let processRunner: ProcessRunner
    private let networkClient: NetworkClient

    public init(
        paths: AppPaths,
        fileSystem: LocalFileSystem,
        logger: AppLogger,
        plistStore: PlistStore,
        processRunner: ProcessRunner,
        networkClient: NetworkClient = DefaultNetworkClient()
    ) {
        self.paths = paths
        self.fileSystem = fileSystem
        self.logger = logger
        self.plistStore = plistStore
        self.processRunner = processRunner
        self.networkClient = networkClient
    }

    public func isRuntimeInstalled() async -> Bool {
        guard fileSystem.fileExists(at: paths.runtimeManifestURL) else {
            return false
        }
        guard let manifest = try? await plistStore.read(RuntimeManifest.self, from: paths.runtimeManifestURL) else {
            return false
        }
        guard (try? validateManifest(manifest)) != nil else {
            return false
        }
        return hasRequiredRuntimeArtifacts()
    }

    public func currentManifest() async -> RuntimeManifest? {
        guard hasRequiredRuntimeArtifacts() else {
            return nil
        }
        do {
            let manifest = try await plistStore.read(RuntimeManifest.self, from: paths.runtimeManifestURL)
            try validateManifest(manifest)
            return manifest
        } catch {
            return nil
        }
    }

    public func fetchLatestReleases() async throws -> RuntimeReleases {
        async let wine = fetchAsset(RuntimeMatrix.wine)
        async let dxvk = fetchAsset(RuntimeMatrix.dxvk)
        async let dxmt = fetchAsset(RuntimeMatrix.dxmt)
        return RuntimeReleases(wine: try await wine, dxvk: try await dxvk, dxmt: try await dxmt)
    }

    public func downloadAll(
        releases: RuntimeReleases,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> DownloadedRuntimeArchives {
        let temp = FileManager.default.temporaryDirectory.appending(path: "ScotchRuntimeDownloads")
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
        try ensureDiskSpace(requiredBytes: archives.runtimeReleases.wine.size + archives.runtimeReleases.dxvk.size + archives.runtimeReleases.dxmt.size)

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
            try await installTranslationLibrary(componentName: "DXVK", archive: archives.dxvkArchive, destination: libraries.appending(path: "DXVK"))
            try await installTranslationLibrary(componentName: "DXMT", archive: archives.dxmtArchive, destination: libraries.appending(path: "DXMT"))

            let overlayResults = try await [
                installOverlay(component: .winemacOpenGLPatch),
                installOverlay(component: .d3dmetal),
                installOverlay(component: .zink)
            ]

            try await installGPUSpoofShim()

            let manifest = RuntimeManifest(
                wineVersion: archives.runtimeReleases.wine.versionTag,
                dxvkVersion: archives.runtimeReleases.dxvk.versionTag,
                dxmtVersion: archives.runtimeReleases.dxmt.versionTag,
                d3dmetalVersion: overlayResults.first(where: { $0.component == .d3dmetal })?.installedVersion,
                winemacPatchVersion: overlayResults.first(where: { $0.component == .winemacOpenGLPatch })?.installedVersion,
                zinkVersion: overlayResults.first(where: { $0.component == .zink })?.installedVersion
            )

            try validateManifest(manifest)
            try verifyInstalledArtifacts()

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
            throw error
        }
    }

    public func shouldUpdateRuntime() async -> (Bool, AppVersion) {
        guard let manifest = await currentManifest() else {
            return (false, AppVersion(0, 0, 0))
        }
        let expectedWine = RuntimeMatrix.wine.versionTag
        let expectedDXVK = RuntimeMatrix.dxvk.versionTag
        let expectedDXMT = RuntimeMatrix.dxmt.versionTag
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
        if manifest.winemacPatchVersion != OverlayVersion.winemac {
            drifts.append(OverlayDrift(component: .winemacOpenGLPatch, installedVersion: manifest.winemacPatchVersion, expectedVersion: OverlayVersion.winemac))
        }
        if manifest.d3dmetalVersion != OverlayVersion.d3dmetal {
            drifts.append(OverlayDrift(component: .d3dmetal, installedVersion: manifest.d3dmetalVersion, expectedVersion: OverlayVersion.d3dmetal))
        }
        if manifest.zinkVersion != OverlayVersion.zink {
            drifts.append(OverlayDrift(component: .zink, installedVersion: manifest.zinkVersion, expectedVersion: OverlayVersion.zink))
        }
        return drifts
    }

    private func fetchAsset(_ requirement: RuntimeAssetRequirement) async throws -> ReleaseAsset {
        guard let url = URL(string: "https://api.github.com/repos/\(requirement.repo)/releases/tags/\(requirement.versionTag)") else {
            throw RuntimeInstallerError.invalidURL
        }

        let request = NetworkRequest(
            url: url,
            headers: ["Accept": "application/vnd.github+json"]
        )

        do {
            let data = try await networkClient.data(for: request)
            let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
            guard release.tagName == requirement.versionTag else {
                throw RuntimeInstallerError.releaseDiscoveryFailed(
                    "\(requirement.repo): expected tag \(requirement.versionTag), got \(release.tagName)"
                )
            }
            if release.draft == true {
                throw RuntimeInstallerError.releaseDiscoveryFailed("\(requirement.repo): release \(requirement.versionTag) is marked as draft")
            }
            if release.prerelease == true {
                throw RuntimeInstallerError.releaseDiscoveryFailed("\(requirement.repo): release \(requirement.versionTag) is marked as prerelease")
            }
            let asset = release.assets.first(where: { asset in
                requirement.assetNamePatterns.allSatisfy { asset.name.contains($0) }
            })

            guard let matched = asset else {
                throw RuntimeInstallerError.missingAsset("\(requirement.displayName) \(requirement.versionTag) in \(requirement.repo)")
            }

            return ReleaseAsset(
                name: matched.name,
                versionTag: requirement.versionTag,
                downloadURL: matched.browserDownloadURL,
                size: matched.size,
                sha256: await resolveChecksumIfAvailable(for: matched.name, in: release.assets)
            )
        } catch let error as RuntimeInstallerError {
            throw error
        } catch {
            throw RuntimeInstallerError.releaseDiscoveryFailed("\(requirement.repo): \(error.localizedDescription)")
        }
    }

    private func downloadAsset(
        _ asset: ReleaseAsset,
        into directory: URL,
        reportBytes: @Sendable @escaping (Int64) -> Void
    ) async throws -> URL {
        let destination = directory.appending(path: asset.name)

        do {
            let temporaryFile = try await networkClient.download(from: NetworkRequest(url: asset.downloadURL))
            if fileSystem.fileExists(at: destination) {
                try fileSystem.removeItem(at: destination)
            }
            try fileSystem.moveItem(at: temporaryFile, to: destination)
            if let expectedChecksum = asset.sha256 {
                try verifyChecksum(expectedChecksum, for: destination, assetName: asset.name)
            }
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
        let scratch = paths.applicationSupportDirectory.appending(path: "wine-scratch")
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
        let scratch = paths.applicationSupportDirectory.appending(path: "\(componentName.lowercased())-scratch")
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
        try fileSystem.moveItem(at: x64Dir, to: destination.appending(path: "x64"))
        try fileSystem.moveItem(at: x32Dir, to: destination.appending(path: "x32"))

        for unix in unixDirs {
            try mergeWineExtension(from: unix)
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

    private func createWineAppBundle() throws {
        let bundleURL = paths.wineBundleURL
        let contents = bundleURL.appending(path: "Contents")
        let macOS = contents.appending(path: "MacOS")

        if fileSystem.fileExists(at: bundleURL) {
            try fileSystem.removeItem(at: bundleURL)
        }
        try fileSystem.createDirectory(at: macOS)

        let launcherURL = macOS.appending(path: "wine-launcher")
        try wineLauncherScript.write(to: launcherURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherURL.path(percentEncoded: false))
        try wineInfoPlist.write(to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }

    private func installOverlay(component: OverlayComponent) async throws -> OverlayInstallResult {
        let descriptor = overlayDescriptor(for: component)
        guard let url = URL(string: "https://github.com/S3bRR/Scotch/releases/download/\(descriptor.versionTag)/\(descriptor.fileName)") else {
            throw RuntimeInstallerError.installFailed("Invalid overlay URL for \(component.displayName)")
        }

        let archive = try await downloadOverlay(from: url, fileName: descriptor.fileName)
        try await TarArchive.extract(archive, to: descriptor.extractDestination, using: processRunner)
        try verifyOverlayInstall(component: component)
        logger.info("Installed overlay \(component.displayName) version \(descriptor.versionTag)")
        return OverlayInstallResult(component: component, installedVersion: descriptor.versionTag, errorMessage: nil)
    }

    private func overlayDescriptor(for component: OverlayComponent) -> (versionTag: String, fileName: String, extractDestination: URL) {
        switch component {
        case .winemacOpenGLPatch:
            (OverlayVersion.winemac, "winemac-openglpatch-11.6.tar.gz", paths.librariesDirectory.appending(path: "Wine"))
        case .d3dmetal:
            (OverlayVersion.d3dmetal, "d3dmetal-3.0.tar.gz", paths.librariesDirectory)
        case .zink:
            (OverlayVersion.zink, "zink-1.0.tar.gz", paths.librariesDirectory)
        }
    }

    private func verifyOverlayInstall(component: OverlayComponent) throws {
        switch component {
        case .winemacOpenGLPatch:
            let winemac = paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so")
            guard fileSystem.fileExists(at: winemac) else {
                throw RuntimeInstallerError.installFailed("winemac overlay verification failed: winemac.so missing")
            }

            let handle = try FileHandle(forReadingFrom: winemac)
            defer { try? handle.close() }
            try handle.seek(toOffset: 0x3290f)
            let byte = try handle.read(upToCount: 1)?.first ?? 0
            guard byte == 0x90 else {
                throw RuntimeInstallerError.installFailed(
                    "winemac overlay verification failed: sentinel byte mismatch at 0x3290f (got 0x\(String(byte, radix: 16)))"
                )
            }
        case .d3dmetal:
            let d3d12DLL = paths.librariesDirectory.appending(path: "D3DMetal/x64/d3d12.dll")
            guard fileSystem.fileExists(at: d3d12DLL) else {
                throw RuntimeInstallerError.installFailed("D3DMetal overlay verification failed: x64/d3d12.dll missing")
            }

            let frameworkBinary = paths.librariesDirectory.appending(path: "D3DMetal/D3DMetal.framework/Versions/A/D3DMetal")
            guard fileSystem.fileExists(at: frameworkBinary) else {
                throw RuntimeInstallerError.installFailed("D3DMetal overlay verification failed: framework binary missing")
            }
        case .zink:
            let marker = paths.librariesDirectory.appending(path: "Zink/x64/opengl32.dll")
            guard fileSystem.fileExists(at: marker) else {
                throw RuntimeInstallerError.installFailed("Zink overlay verification failed: x64/opengl32.dll missing")
            }
        }
    }

    private func downloadOverlay(from url: URL, fileName: String) async throws -> URL {
        let destinationDirectory = FileManager.default.temporaryDirectory.appending(path: "ScotchOverlays")
        if !fileSystem.fileExists(at: destinationDirectory) {
            try fileSystem.createDirectory(at: destinationDirectory)
        }
        let destination = destinationDirectory.appending(path: fileName)

        do {
            let temporary = try await networkClient.download(from: NetworkRequest(url: url))
            if fileSystem.fileExists(at: destination) {
                try fileSystem.removeItem(at: destination)
            }
            try fileSystem.moveItem(at: temporary, to: destination)
            return destination
        } catch let NetworkClientError.nonSuccessStatus(_, status) {
            throw RuntimeInstallerError.downloadFailed("Overlay \(fileName) returned \(status)")
        } catch let networkError as NetworkClientError {
            throw RuntimeInstallerError.downloadFailed("Overlay \(fileName): \(networkError.errorDescription ?? "unknown")")
        } catch let runtimeError as RuntimeInstallerError {
            throw runtimeError
        } catch {
            throw RuntimeInstallerError.downloadFailed("Overlay \(fileName): \(error.localizedDescription)")
        }
    }

    private func resolveChecksumIfAvailable(
        for assetName: String,
        in releaseAssets: [GitHubReleaseResponse.Asset]
    ) async -> String? {
        guard let checksumAsset = findChecksumAsset(for: assetName, in: releaseAssets) else {
            return nil
        }

        do {
            let request = NetworkRequest(
                url: checksumAsset.browserDownloadURL,
                headers: ["Accept": "application/vnd.github+json"]
            )
            let data = try await networkClient.data(for: request)
            guard let manifestText = String(data: data, encoding: .utf8) else {
                logger.warning("Checksum fetch for \(assetName) returned non-UTF8 content")
                return nil
            }
            if let parsed = SHA256Checksum.parse(manifestText, targetFileName: assetName) {
                return parsed
            }
            logger.warning("Checksum manifest for \(assetName) did not include a SHA256 entry")
            return nil
        } catch {
            logger.warning("Checksum fetch failed for \(assetName): \(error.localizedDescription)")
            return nil
        }
    }

    private func findChecksumAsset(
        for assetName: String,
        in releaseAssets: [GitHubReleaseResponse.Asset]
    ) -> GitHubReleaseResponse.Asset? {
        let normalizedAssetName = assetName.lowercased()
        let explicitCandidates = [
            "\(normalizedAssetName).sha256",
            "\(normalizedAssetName).sha256sum",
            "\(normalizedAssetName).sha256.txt",
            "sha256sums",
            "sha256sums.txt",
            "sha256sum.txt",
            "checksums",
            "checksums.txt"
        ]

        if let exact = releaseAssets.first(where: { asset in
            let candidate = asset.name.lowercased()
            return explicitCandidates.contains(candidate)
        }) {
            return exact
        }

        return releaseAssets.first(where: { asset in
            let candidate = asset.name.lowercased()
            return candidate.contains("sha256") || candidate.contains("checksum")
        })
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
        let sourceURL =
            Bundle.module.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib", subdirectory: "VulkanSpoof")
            ?? Bundle.module.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib")

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

    private var wineLauncherScript: String {
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
        if [ -d "$LIBS/D3DMetal" ]; then
          export DYLD_FRAMEWORK_PATH="$LIBS/D3DMetal${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
          export DYLD_LIBRARY_PATH="$LIBS/D3DMetal${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        fi
        if [ -n "${SCOTCH_GPU_SPOOF_LIB:-}" ] && [ -f "$SCOTCH_GPU_SPOOF_LIB" ]; then
          export CX_LIBVULKAN="$SCOTCH_GPU_SPOOF_LIB"
          export SCOTCH_REAL_MOLTENVK_PATH="${SCOTCH_REAL_MOLTENVK_PATH:-$LIBS/Wine/lib/libMoltenVK.dylib}"
          export DYLD_LIBRARY_PATH="$(dirname "$SCOTCH_GPU_SPOOF_LIB")${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
        fi
        export PATH="$LIBS/Wine/bin:${PATH:-/usr/bin:/bin}"
        export WINE="${WINE:-$LIBS/Wine/bin/wine}"
        exec "$LIBS/Wine/bin/wine" "$@"
        """
    }

    private func cleanupTransientInstallFiles() {
        let transients = [
            FileManager.default.temporaryDirectory.appending(path: "ScotchRuntimeDownloads"),
            FileManager.default.temporaryDirectory.appending(path: "ScotchOverlays"),
            paths.applicationSupportDirectory.appending(path: "wine-scratch"),
            paths.applicationSupportDirectory.appending(path: "dxvk-scratch"),
            paths.applicationSupportDirectory.appending(path: "dxmt-scratch")
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
            paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so"),
            paths.librariesDirectory.appending(path: "D3DMetal/x64/d3d12.dll"),
            paths.librariesDirectory.appending(path: "D3DMetal/D3DMetal.framework/Versions/A/D3DMetal"),
            paths.librariesDirectory.appending(path: "Zink/x64/opengl32.dll"),
            paths.librariesDirectory.appending(path: "VulkanSpoof/libscotch_gpu_spoof.dylib")
        ]

        for path in requiredPaths where !fileSystem.fileExists(at: path) {
            throw RuntimeInstallerError.installFailed("Post-install verification failed: missing \(path.path(percentEncoded: false))")
        }

        try verifyOverlayInstall(component: .winemacOpenGLPatch)
        try verifyOverlayInstall(component: .d3dmetal)
        try verifyOverlayInstall(component: .zink)
    }

    private func validateManifest(_ manifest: RuntimeManifest) throws {
        if manifest.wineVersion.isEmpty || manifest.dxvkVersion.isEmpty || manifest.dxmtVersion.isEmpty {
            throw RuntimeInstallerError.installFailed("Manifest sanity check failed: missing core runtime versions")
        }
        let overlays = [
            manifest.winemacPatchVersion,
            manifest.d3dmetalVersion,
            manifest.zinkVersion
        ]
        if overlays.contains(where: { ($0 ?? "").isEmpty }) {
            throw RuntimeInstallerError.installFailed("Manifest sanity check failed: missing required overlay versions")
        }
    }

    private func hasRequiredRuntimeArtifacts() -> Bool {
        let requiredPaths = [
            paths.wineBinaryURL,
            paths.wineBundleURL,
            paths.librariesDirectory.appending(path: "DXVK"),
            paths.librariesDirectory.appending(path: "DXMT"),
            paths.librariesDirectory.appending(path: "Wine/lib/wine/x86_64-unix/winemac.so"),
            paths.librariesDirectory.appending(path: "D3DMetal/x64/d3d12.dll"),
            paths.librariesDirectory.appending(path: "D3DMetal/D3DMetal.framework/Versions/A/D3DMetal"),
            paths.librariesDirectory.appending(path: "Zink/x64/opengl32.dll"),
            paths.librariesDirectory.appending(path: "VulkanSpoof/libscotch_gpu_spoof.dylib")
        ]
        return requiredPaths.allSatisfy { fileSystem.fileExists(at: $0) }
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
