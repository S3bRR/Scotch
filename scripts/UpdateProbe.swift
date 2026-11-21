import Foundation
import CryptoKit
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime
import Darwin

@main
struct UpdateProbe {
    static func main() async {
        do {
            let repo = URL(fileURLWithPath: CommandLine.arguments[1])
            try verifyPublishedFeeds(repo: repo)
            if !CommandLine.arguments.contains("--feed-only") { try await exerciseUpdates(repo: repo) }
            print("Update verification passed.")
        } catch {
            FileHandle.standardError.write(Data("Update verification failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    static func verifyPublishedFeeds(repo: URL) throws {
        _ = try RuntimeFeedVerifier.decode(Data(contentsOf: repo.appending(path: "updates/runtime.json")), publicKey: UpdateConfiguration.runtimePublicKey)
        let xml = try Data(contentsOf: repo.appending(path: "updates/appcast.xml"))
        let text = String(decoding: xml, as: UTF8.self)
        let regex = try NSRegularExpression(pattern: "<!-- sparkle-signatures:\\s*edSignature: ([A-Za-z0-9+/=]+)\\s*length: ([0-9]+)\\s*-->\\s*$")
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let signatureRange = Range(match.range(at: 1), in: text), let lengthRange = Range(match.range(at: 2), in: text),
              let signature = Data(base64Encoded: String(text[signatureRange])), let length = Int(text[lengthRange]), length <= xml.count,
              let marker = Range(match.range, in: text), text[..<marker.lowerBound].utf8.count == length else { throw ProbeError("Appcast signature metadata missing") }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: "9yIFm7v7AZzHk/XRbF/ruSLj4BVXKGCG6RmaiO0Tz7k=")!)
        try expect(key.isValidSignature(signature, for: xml.prefix(length)), "Appcast signature rejected")
        print("Passed: committed app and runtime feeds verify with embedded public keys")
    }
    static func exerciseUpdates(repo: URL) async throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.UpdateProbe.\(UUID().uuidString)")
        let root = paths.applicationSupportDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: paths.cachesDirectory) }
        let cache = RuntimeDownloadCache(paths: paths)
        let cacheDir = paths.cachesDirectory.appending(path: "RuntimePackages")
        let archive = cacheDir.appending(path: String(repeating: "a", count: 64))
        let keep = paths.cachesDirectory.appending(path: "keep")
        try write("keep", to: keep)
        try write("archive", to: archive)
        try fm.createSymbolicLink(at: cacheDir.appending(path: String(repeating: "b", count: 64)), withDestinationURL: keep)
        try expect(try cache.size() == 7, "Cache measurement included unrelated files")
        try expect(try cache.clear(activity: UpdateActivity(processCheck: { false })) == 7, "Cache did not clear the package")
        try expect(try cache.size() == 0 && fm.fileExists(atPath: keep.path), "Cache cleanup touched unrelated data")
        let network = ProbeNetwork()
        let engine = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCOTCH_TEST_ENGINE_IMAGE"] ?? repo.appending(path: ".build/runtime-fixtures/WineForge-0.6.0.3.dmg").path)
        await network.setDownload(MetalEngineInstallation.asset.downloadURL, data: try Data(contentsOf: engine, options: .mappedIfSafe))
        let fixtures = root.appending(path: "fixtures")
        try fm.createDirectory(at: fixtures, withIntermediateDirectories: true)
        func package(_ component: RuntimeComponent, files: [String]) async throws -> [String: Any] {
            let folder = fixtures.appending(path: component.rawValue)
            for file in files {
                let url = folder.appending(path: file)
                try write("fixture", to: url)
                if file == "wine/bin/wine" {
                    try write("#!/bin/sh\necho wine-11.16\n", to: url)
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
                if file.hasSuffix(".dll") {
                    var pe = Data(repeating: 0, count: 256)
                    pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 128
                    pe[128] = 0x50; pe[129] = 0x45
                    let x64 = file.hasPrefix("x64/") || file.hasPrefix("x86_64-windows/")
                    pe[132] = x64 ? 0x64 : 0x4c; pe[133] = x64 ? 0x86 : 0x01
                    try pe.write(to: url)
                }
            }
            let archive = fixtures.appending(path: "\(component.rawValue).tar.gz")
            _ = try await DefaultProcessRunner().captureProcess(ProcessSpecification(executableURL: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-czf", archive.path, "-C", folder.path, "."], displayName: "Create fixture"), outputFileHandle: nil)
            let bytes = try Data(contentsOf: archive)
            let url = URL(string: "https://github.com/ScotchProbe/Fixtures/releases/download/v1/\(component.rawValue).tar.gz")!
            await network.setDownload(url, data: bytes)
            return ["component": component.rawValue, "version": component == .wine ? "11.16" : "1.0", "url": url.absoluteString, "fileName": archive.lastPathComponent, "size": bytes.count, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()]
        }
        var packages: [[String: Any]] = []
        packages.append(try await package(.wine, files: ["wine/bin/wine", "wine/bin/wineserver", "wine/lib/wine/x86_64-unix/winemac.so", "wine/share/wine/mono/wine-mono-11.3.0/lib/mono/4.5/mscorlib.dll", "wine/share/wine/gecko/wine-gecko-2.47.4-x86_64/xul.dll", "wine/share/wine/gecko/wine-gecko-2.47.4-x86/xul.dll"]))
        packages.append(try await package(.dxvk, files: ["x64/d3d11.dll", "x32/d3d11.dll"]))
        var dxmt = try await package(.dxmt, files: ["x86_64-windows/d3d11.dll", "i386-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "i386-windows/dxgi.dll", "x86_64-windows/winemetal.dll", "i386-windows/winemetal.dll", "x86_64-unix/winemetal.so"])
        dxmt["layoutVersion"] = 2
        packages.append(dxmt)
        packages.append(try await package(.zink, files: ["x64/opengl32.dll", "x64/libgallium_wgl.dll", "x64/libEGL.dll", "x64/libGLESv1_CM.dll", "x64/libGLESv2.dll", "x86/opengl32.dll", "x86/libgallium_wgl.dll", "x86/libEGL.dll", "x86/libGLESv1_CM.dll", "x86/libGLESv2.dll"]))
        let runtime: [String: Any] = ["id": "approved-fixture-1", "title": "Fixture Runtime 1", "minimumAppBuild": 12, "minimumMacOS": 26, "architecture": "arm64", "packages": packages]
        func envelope(revision: Int = 2, sets: [[String: Any]]? = nil, expiry: String = "2030-01-01T00:00:00Z") throws -> Data {
            let payload = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "revision": revision, "validUntil": expiry, "sets": sets ?? [runtime]], options: .sortedKeys)
            return try JSONEncoder().encode(SignedUpdateEnvelope(payload: payload.base64EncodedString(), signature: key.signature(for: payload).base64EncodedString()))
        }
        // Public memberwise initializers are intentionally not needed by the client.
        let valid = try envelope()
        _ = try RuntimeFeedVerifier.decode(valid, publicKey: publicKey)
        var tampered = try JSONSerialization.jsonObject(with: valid) as! [String: String]
        tampered["payload"] = Data("tampered".utf8).base64EncodedString()
        try rejects("modified payload") { _ = try RuntimeFeedVerifier.decode(JSONSerialization.data(withJSONObject: tampered), publicKey: publicKey) }
        try rejects("wrong key") { _ = try RuntimeFeedVerifier.decode(valid, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()) }
        try rejects("expired feed") { _ = try RuntimeFeedVerifier.decode(envelope(expiry: "2000-01-01T00:00:00Z"), publicKey: publicKey) }
        var unsafe = runtime; unsafe["id"] = "../escape"
        try rejects("unsafe set path") { _ = try RuntimeFeedVerifier.decode(envelope(sets: [unsafe]), publicKey: publicKey) }
        var badPackages = packages; badPackages[0]["url"] = "http://attacker.test/archive.tar"
        unsafe = runtime; unsafe["packages"] = badPackages
        try rejects("insecure/unapproved asset host") { _ = try RuntimeFeedVerifier.decode(envelope(sets: [unsafe]), publicKey: publicKey) }
        print("Passed: modified, wrong-key, expired, traversal, and unapproved-host feeds rejected")

        let activity = UpdateActivity(processCheck: { false })
        var operation: UpdateLease? = try activity.beginOperation()
        try rejects("maintenance during operation") { _ = try activity.acquireMaintenance() }
        withExtendedLifetime(operation) {}; operation = nil
        var exclusive: UpdateLease? = try activity.acquireMaintenance()
        try rejects("launch during update") { _ = try activity.beginOperation() }
        withExtendedLifetime(exclusive) {}; exclusive = nil
        try rejects("running game") { _ = try UpdateActivity(processCheck: { true }).acquireMaintenance() }
        print("Passed: operations and updates exclude each other; running games block activation")

        var future = runtime
        future["id"] = "future-client-layout"
        future["minimumAppBuild"] = (Int(ScotchAppInfo.build) ?? 0) + 1
        var futurePackages = packages; futurePackages[2]["layoutVersion"] = 99
        future["packages"] = futurePackages
        let futurePaths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.FutureFeedProbe.\(UUID().uuidString)")
        defer { try? fm.removeItem(at: futurePaths.applicationSupportDirectory); try? fm.removeItem(at: futurePaths.cachesDirectory) }
        let futureService = RuntimeUpdateService(paths: futurePaths, network: network, logger: ProbeLogger(), publicKey: publicKey, activity: activity)
        await network.setFeed(try envelope(sets: [runtime, future]))
        guard case .incompatible = try await futureService.check(force: true) else { throw ProbeError("A future runtime must continue through the app update flow") }
        print("Passed: future signed layouts preserve the app-first update path instead of invalidating the whole feed")

        let service = RuntimeUpdateService(paths: paths, network: network, logger: ProbeLogger(), publicKey: publicKey, activity: activity)
        await network.setFeed(valid)
        guard case .available(let target) = try await service.check(force: true) else { throw ProbeError("Update not offered") }
        let oldBottles = root.appending(path: "custom-prefixes")
        let bottleURL = oldBottles.appending(path: "game")
        let settings = BottleSettings(info: BottleInfo(name: "Game"))
        let store = PlistStore()
        try await store.write(settings, to: bottleURL.appending(path: BottleSettings.metadataFileName))
        try write("saved progress", to: bottleURL.appending(path: "drive_c/users/steam/Saves/save.dat"))
        let catalog = BottleCatalog(bottlePaths: [bottleURL.path, "/Volumes/OfflineGames/PreservedBottle"])
        try await store.write(catalog, to: paths.bottleCatalogURL)
        let originalCatalog = try Data(contentsOf: paths.bottleCatalogURL)
        let originalMetadata = try Data(contentsOf: bottleURL.appending(path: BottleSettings.metadataFileName))
        try await service.install(target)
        try expect(paths.defaultRuntimeSetID == target.id, "Default selection not committed")
        try expect(try Data(contentsOf: paths.bottleCatalogURL) == originalCatalog, "Catalog changed while updating runtime")
        try expect(try Data(contentsOf: bottleURL.appending(path: BottleSettings.metadataFileName)) == originalMetadata, "Existing bottle was silently upgraded")
        try expect(try String(contentsOf: bottleURL.appending(path: "drive_c/users/steam/Saves/save.dat"), encoding: .utf8) == "saved progress", "Save data changed")
        let count = await network.downloadCount
        try await service.install(target)
        try expect(await network.downloadCount == count, "An installed set was redownloaded")
        try expect(try await service.check(force: true) == .current, "Update did not clear")
        let restarted = RuntimeUpdateService(paths: paths, network: network, logger: ProbeLogger(), publicKey: publicKey, activity: activity)
        try expect(try await restarted.check() == .current, "Restart repeats installed update")
        try fm.removeItem(at: paths.forRuntimeSet(target.id).librariesDirectory.appending(path: "Zink/x64/opengl32.dll"))
        guard case .repair = try await service.check(force: true) else { throw ProbeError("Damaged runtime not offered for repair") }
        try await service.install(target)
        try expect(try await service.check(force: true) == .current, "Repair did not clear")
        try expect(await network.downloadCount == count, "Repair failed to reuse verified package cache")
        print("Passed: a damaged selected runtime is atomically repaired without redownloads or prefix changes")
        await network.setFeed(try envelope(revision: 1))
        do { _ = try await restarted.check(force: true); throw ProbeError("Older feed accepted") } catch is RuntimeUpdateError {}
        print("Passed: authenticated install commits once, clears after restart, preserves external catalog and saves, and rejects replay")
        var metalRuntime = runtime
        metalRuntime["id"] = "missing-approved-d3dmetal"
        metalRuntime["minimumAppBuild"] = 12
        let missingMetal: [String: Any] = ["component": "d3dmetal", "layoutVersion": 3, "version": "3.0", "url": "https://github.com/ScotchProbe/Fixtures/releases/download/v1/missing-metal.tar.xz", "fileName": "missing-metal.tar.xz", "size": 1, "sha256": String(repeating: "0", count: 64)]
        metalRuntime["packages"] = packages + [missingMetal]
        var tooOld = metalRuntime; tooOld["minimumAppBuild"] = 11
        try rejects("D3DMetal loader minimum build") { _ = try RuntimeFeedVerifier.decode(envelope(revision: 3, sets: [tooOld]), publicKey: publicKey) }
        await network.setFeed(try envelope(revision: 3, sets: [metalRuntime]))
        guard case .available(let metalTarget) = try await service.check(force: true) else { throw ProbeError("D3DMetal candidate missing") }
        do { try await service.install(metalTarget); throw ProbeError("Incomplete approved D3DMetal set was activated") }
        catch is RuntimeInstallerError {}
        try expect(paths.defaultRuntimeSetID == target.id, "Missing approved D3DMetal changed default")
        try expect(!fm.fileExists(atPath: paths.forRuntimeSet(metalTarget.id).librariesDirectory.path), "Incomplete approved D3DMetal set was published")
        print("Passed: approved D3DMetal requires its compatible client and cannot be silently omitted from a committed set")
        // A maintainer can accidentally approve the wrong bitness. Such a signed
        // package must still fail staging without changing the active selection.
        let wrongDLL = fixtures.appending(path: "dxvk/x64/d3d11.dll")
        var wrongData = try Data(contentsOf: wrongDLL)
        wrongData[132] = 0x4c; wrongData[133] = 0x01
        try wrongData.write(to: wrongDLL)
        let wrongArchive = fixtures.appending(path: "wrong-dxvk.tar.gz")
        _ = try await DefaultProcessRunner().captureProcess(ProcessSpecification(executableURL: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-czf", wrongArchive.path, "-C", fixtures.appending(path: "dxvk").path, "."], displayName: "Wrong architecture fixture"), outputFileHandle: nil)
        let wrongBytes = try Data(contentsOf: wrongArchive)
        var wrongPackages = packages
        wrongPackages[1]["sha256"] = SHA256.hash(data: wrongBytes).map { String(format: "%02x", $0) }.joined()
        wrongPackages[1]["size"] = wrongBytes.count
        var wrongRuntime = runtime; wrongRuntime["id"] = "wrong-bitness"; wrongRuntime["packages"] = wrongPackages
        let wrongFeed = try envelope(revision: 4, sets: [wrongRuntime])
        await network.setFeed(wrongFeed)
        await network.setDownload(URL(string: packages[1]["url"] as! String)!, data: wrongBytes)
        guard case .available(let wrongTarget) = try await service.check(force: true) else { throw ProbeError("Candidate missing") }
        do { try await service.install(wrongTarget); throw ProbeError("Wrong architecture accepted") }
        catch let error as RuntimeInstallerError { try expect(error.localizedDescription.contains("architecture"), "Expected architecture rejection") }
        try expect(paths.defaultRuntimeSetID == target.id, "Failed staging changed default")
        try expect(!fm.fileExists(atPath: paths.forRuntimeSet(wrongTarget.id).librariesDirectory.path), "Failed runtime was published")
        print("Passed: signed but wrong-architecture runtime is rejected without changing the working runtime")


        var bottle = BottleSummary(id: BottleID(rawValue: "game"), directoryURL: bottleURL, settings: settings, isAvailable: true)
        let manager = BottleRuntimeManager(paths: paths, activity: activity)
        bottle = try await manager.switchRuntime(for: bottle, to: target.id)
        try expect(bottle.settings.runtimeSetID == target.id, "Runtime switch failed")
        let selected = paths.forBottle(bottle)
        let environment = EnvironmentAssembler(paths: selected).makeWineEnvironment(bottle: bottle)
        try expect(environment["WINE"]?.contains("RuntimeSets/" + target.id) == true, "Wine path does not use selected set")
        let worker = WineRuntimeService(paths: paths, processRunner: DefaultProcessRunner(), fileSystem: LocalFileSystem(), logger: ProbeLogger(), logStore: LogStore(logsDirectory: paths.logsDirectory), envAssembler: EnvironmentAssembler(paths: paths))
        let routed = await worker.makeShellEnvironment(for: bottle)
        try expect(routed["PATH"]?.contains("RuntimeSets/" + target.id) == true, "Service ignored bottle runtime")
        let recovery = bottleURL.deletingLastPathComponent().appending(path: ".ScotchPrefixBackups/\(bottleURL.lastPathComponent)")
        try expect(!fm.fileExists(atPath: recovery.deletingLastPathComponent().path), "Runtime switch created a backup directory")
        let savePath = "drive_c/users/steam/Saves/save.dat"
        try expect(try String(contentsOf: bottleURL.appending(path: savePath), encoding: .utf8) == "saved progress", "Runtime switch changed the save")

        // An existing snapshot from an old version can still be activated in place.
        try write("new progress", to: bottleURL.appending(path: savePath))
        let snapshot = recovery.appending(path: "snapshot-legacy")
        try write("saved progress", to: snapshot.appending(path: savePath))
        try await store.write(settings, to: snapshot.appending(path: BottleSettings.metadataFileName))
        try write(snapshot.lastPathComponent, to: recovery.appending(path: "LatestSnapshot"))
        let restored = try await manager.restore(for: bottle)
        try expect(restored.settings.runtimeSetID == nil, "Original runtime selection not restored")
        try expect(try String(contentsOf: bottleURL.appending(path: savePath), encoding: .utf8) == "saved progress", "Original save not restored")
        try expect(try String(contentsOf: snapshot.appending(path: savePath), encoding: .utf8) == "new progress", "The exchanged directory lost the current save")
        try expect(try Set(fm.contentsOfDirectory(atPath: recovery.path)) == ["LatestSnapshot", "snapshot-legacy"], "Restoring created another directory")
        print("Passed: runtime routing and legacy snapshot exchange without copying a prefix")

        try write("unreadable catalog", to: paths.bottleCatalogURL)
        do { try await store.write(catalog, to: paths.bottleCatalogURL); throw ProbeError("Corrupt catalog overwritten") } catch is DecodingError {}
        try expect(try String(contentsOf: paths.bottleCatalogURL, encoding: .utf8) == "unreadable catalog", "Original catalog lost")
        let futureMetadata: [String: Any] = ["fileVersion": ["major": 999, "minor": 0, "patch": 0]]
        let futureData = try PropertyListSerialization.data(fromPropertyList: futureMetadata, format: .xml, options: 0)
        try futureData.write(to: bottleURL.appending(path: BottleSettings.metadataFileName))
        do { try await store.write(settings, to: bottleURL.appending(path: BottleSettings.metadataFileName)); throw ProbeError("Future metadata overwritten") } catch is DecodingError {}
        try expect(try Data(contentsOf: bottleURL.appending(path: BottleSettings.metadataFileName)) == futureData, "Future metadata lost")
        print("Passed: corrupt catalog and future metadata cannot be overwritten by defaults")
    }
}
private struct ProbeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
private func expect(_ condition: Bool, _ message: String) throws { if !condition { throw ProbeError(message) } }
private func rejects(_ message: String, operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw ProbeError("Expected rejection: " + message)
}
private func write(_ value: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(value.utf8).write(to: url)
}
private struct ProbeLogger: AppLogger {
    func info(_ message: String) {}
    func warning(_ message: String) {}
    func error(_ message: String) {}
}
private actor ProbeNetwork: NetworkClient {
    var feed = Data()
    var downloads: [URL: Data] = [:]
    private(set) var downloadCount = 0
    func setFeed(_ data: Data) { feed = data }
    func setDownload(_ url: URL, data: Data) { downloads[url] = data }
    func data(for request: NetworkRequest) async throws -> Data { feed }
    func download(from request: NetworkRequest) async throws -> URL {
        guard let data = downloads[request.url] else { throw ProbeError("Unexpected download " + request.url.absoluteString) }
        downloadCount += 1
        let url = FileManager.default.temporaryDirectory.appending(path: "ScotchUpdateFixture-\(UUID().uuidString)")
        try data.write(to: url)
        return url
    }
}
