import Foundation
import Testing
@testable import ScotchRuntime

struct RuntimeResourcesTests {
    @Test func packagedAppFindsFlattenedResourcesAfterRelocation() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let app = fixture.root.appending(path: "Mounted Volume/Scotch.app")
        let resources = app.appending(path: "Contents/Resources")
        let shim = try fixture.write("shim", at: resources.appending(path: "\(RuntimeResources.bundleName)/libscotch_gpu_spoof.dylib"))
        let cabextract = try fixture.write("cabextract", at: resources.appending(path: "\(RuntimeResources.bundleName)/cabextract"))
        let lookup = RuntimeResources(resourceURL: resources, executableURL: app.appending(path: "Contents/MacOS/ScotchApp"))
        #expect(lookup.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib", subdirectory: "VulkanSpoof") == shim)
        #expect(lookup.url(forResource: "cabextract", withExtension: nil) == cabextract)
    }

    @Test func swiftPMExecutableFindsSiblingBundleWithPreservedFolders() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let output = fixture.root.appending(path: ".build/arm64-apple-macosx/release")
        let shim = try fixture.write("shim", at: output.appending(path: "\(RuntimeResources.bundleName)/VulkanSpoof/libscotch_gpu_spoof.dylib"))
        let lookup = RuntimeResources(resourceURL: nil, executableURL: output.appending(path: "ScotchCmd"))
        #expect(lookup.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib", subdirectory: "VulkanSpoof") == shim)
    }

    @Test func thumbnailExtensionFindsContainingAppResources() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let app = fixture.root.appending(path: "Scotch.app")
        let resources = app.appending(path: "Contents/Resources")
        let cabextract = try fixture.write("cabextract", at: resources.appending(path: "\(RuntimeResources.bundleName)/cabextract"))
        let extensionContents = app.appending(path: "Contents/PlugIns/ScotchThumbnail.appex/Contents")
        let lookup = RuntimeResources(resourceURL: extensionContents.appending(path: "Resources"), executableURL: extensionContents.appending(path: "MacOS/ScotchThumbnail"))
        #expect(lookup.url(forResource: "cabextract", withExtension: nil) == cabextract)
    }

    @Test func missingBundleAndMissingFileReturnNil() throws {
        let fixture = try ResourceFixture()
        defer { fixture.remove() }
        let lookup = RuntimeResources(resourceURL: fixture.root, executableURL: nil)
        #expect(lookup.url(forResource: "cabextract", withExtension: nil) == nil)
        try FileManager.default.createDirectory(at: fixture.root.appending(path: RuntimeResources.bundleName), withIntermediateDirectories: true)
        #expect(lookup.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib") == nil)
        try FileManager.default.createDirectory(at: fixture.root.appending(path: "\(RuntimeResources.bundleName)/cabextract"), withIntermediateDirectories: true)
        #expect(lookup.url(forResource: "cabextract", withExtension: nil) == nil)
    }

    @Test func actualSwiftPMResourcesAreResolvable() {
        #expect(RuntimeResources.bundled.url(forResource: "libscotch_gpu_spoof", withExtension: "dylib", subdirectory: "VulkanSpoof") != nil)
        #expect(RuntimeResources.bundled.url(forResource: "cabextract", withExtension: nil) != nil)
    }
}

private struct ResourceFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ScotchResourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ contents: String, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
