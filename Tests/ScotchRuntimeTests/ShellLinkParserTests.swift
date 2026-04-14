import Foundation
import Testing
@testable import ScotchRuntime

struct ShellLinkParserTests {
    @Test func parsesUnicodeLinkIntoBottleExecutablePath() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let linkURL = tempDirectory.appending(path: "game.lnk")
        let windowsPath = #"C:\Program Files\Game\game.exe"#
        let linkData = makeUnicodeShellLinkData(for: windowsPath)
        try linkData.write(to: linkURL)

        let bottleDirectory = URL(fileURLWithPath: "/tmp/scotch-shelllink-bottle")
        let parsed = ShellLinkParser.executableURL(from: linkURL, bottleDirectory: bottleDirectory)

        #expect(parsed?.path(percentEncoded: false) == "/tmp/scotch-shelllink-bottle/drive_c/Program Files/Game/game.exe")
    }

    private func makeUnicodeShellLinkData(for path: String) -> Data {
        let headerSize: UInt32 = 0x4C
        let linkInfoHeaderSize: UInt32 = 0x24
        let pathData = (path.data(using: .utf16LittleEndian) ?? Data()) + Data([0, 0])
        let linkInfoSize = linkInfoHeaderSize + UInt32(pathData.count)

        var data = Data(repeating: 0, count: Int(headerSize))
        writeUInt32(headerSize, into: &data, at: 0)
        writeUInt32(1 << 1, into: &data, at: 0x14) // hasLinkInfo

        var linkInfo = Data(repeating: 0, count: Int(linkInfoHeaderSize))
        writeUInt32(linkInfoSize, into: &linkInfo, at: 0)
        writeUInt32(linkInfoHeaderSize, into: &linkInfo, at: 4)
        writeUInt32(1 << 0, into: &linkInfo, at: 8) // volumeIDAndLocalBasePath
        writeUInt32(linkInfoHeaderSize, into: &linkInfo, at: 28) // localBasePathOffsetUnicode
        linkInfo.append(pathData)

        data.append(linkInfo)
        return data
    }

    private func writeUInt32(_ value: UInt32, into data: inout Data, at offset: Int) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.replaceSubrange(offset..<(offset + 4), with: bytes)
        }
    }
}

