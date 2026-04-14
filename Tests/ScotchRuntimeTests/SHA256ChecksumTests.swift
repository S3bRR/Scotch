import Foundation
import Testing
@testable import ScotchRuntime

struct SHA256ChecksumTests {
    @Test func parsesSha256SumStyleLine() {
        let manifest = """
        d2d2f51ceafa6ea2fe7d7f1db9bc1af76ef3a844ec8a6f4791d57f8f8ab0711b  dxvk-macOS-async-2.4-repack.tar
        """

        let parsed = SHA256Checksum.parse(manifest, targetFileName: "dxvk-macOS-async-2.4-repack.tar")
        #expect(parsed == "d2d2f51ceafa6ea2fe7d7f1db9bc1af76ef3a844ec8a6f4791d57f8f8ab0711b")
    }

    @Test func parsesBsdStyleLine() {
        let manifest = """
        SHA256 (wine-staging-11.0-osx64.tar.xz) = 4f5d4b8e28b6a28b338ac2aebfef4e6ad95e5f404f00bc76f5032c9fd65d3b40
        """

        let parsed = SHA256Checksum.parse(manifest, targetFileName: "wine-staging-11.0-osx64.tar.xz")
        #expect(parsed == "4f5d4b8e28b6a28b338ac2aebfef4e6ad95e5f404f00bc76f5032c9fd65d3b40")
    }

    @Test func hashesFileToKnownDigest() throws {
        let payload = Data("scotch-checksum".utf8)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")
        try payload.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let digest = try SHA256Checksum.hashFile(at: fileURL)
        #expect(digest == "83ce748f057e9ac7de47a17db1c0fab5d2880ec81160988490e8e83da8f3e050")
    }
}
