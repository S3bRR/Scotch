import Foundation
import Testing
@testable import ScotchInfrastructure

struct DLLSwapTests {
    @Test func replaceDLLsThrowsWhenSourceDirectoryMissing() throws {
        let fs = LocalFileSystem()
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchV2-DLLSwap-\(UUID().uuidString)")
        let destination = root.appending(path: "system32")
        let missingSource = root.appending(path: "missing-source")

        defer { try? fs.removeItem(at: root) }
        try fs.createDirectory(at: destination)

        var didThrow = false
        do {
            try fs.replaceDLLs(in: destination, from: missingSource)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test func replaceDLLsThrowsWhenSourceContainsNoDLLs() throws {
        let fs = LocalFileSystem()
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchV2-DLLSwap-\(UUID().uuidString)")
        let destination = root.appending(path: "system32")
        let source = root.appending(path: "source")

        defer { try? fs.removeItem(at: root) }
        try fs.createDirectory(at: destination)
        try fs.createDirectory(at: source)
        try Data("not a dll".utf8).write(to: source.appending(path: "readme.txt"))

        var didThrow = false
        do {
            try fs.replaceDLLs(in: destination, from: source)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
