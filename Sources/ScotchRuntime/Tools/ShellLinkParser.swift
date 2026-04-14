import Foundation

struct ShellLinkParser {
    private static let linkFlagHasLinkTargetIDList: UInt32 = 1 << 0
    private static let linkFlagHasLinkInfo: UInt32 = 1 << 1
    private static let linkInfoFlagVolumeIDAndLocalBasePath: UInt32 = 1 << 0

    static func executableURL(from linkURL: URL, bottleDirectory: URL) -> URL? {
        guard let data = try? Data(contentsOf: linkURL), data.count > 0x4C else {
            return nil
        }

        guard let headerSize = readUInt32(data, at: 0),
              headerSize >= 0x4C,
              let linkFlags = readUInt32(data, at: 0x14) else {
            return nil
        }

        var offset = Int(headerSize)
        if (linkFlags & linkFlagHasLinkTargetIDList) != 0 {
            guard let idListSize = readUInt16(data, at: offset) else { return nil }
            offset += Int(idListSize) + 2
        }

        guard (linkFlags & linkFlagHasLinkInfo) != 0 else {
            return nil
        }

        guard let linkInfoSize = readUInt32(data, at: offset),
              let linkInfoHeaderSize = readUInt32(data, at: offset + 4),
              let linkInfoFlags = readUInt32(data, at: offset + 8),
              (linkInfoFlags & linkInfoFlagVolumeIDAndLocalBasePath) != 0 else {
            return nil
        }

        let linkInfoStart = offset
        let localPathOffsetValue: UInt32?
        let unicode = linkInfoHeaderSize >= 0x24
        if unicode {
            localPathOffsetValue = readUInt32(data, at: offset + 28)
        } else {
            localPathOffsetValue = readUInt32(data, at: offset + 16)
        }

        guard let localPathOffsetValue else { return nil }
        let localPathOffset = linkInfoStart + Int(localPathOffsetValue)

        let windowsPath: String?
        if unicode {
            windowsPath = readUTF16CString(data, at: localPathOffset)
        } else {
            windowsPath = readASCIICString(data, at: localPathOffset)
        }

        guard let windowsPath,
              !windowsPath.isEmpty else { return nil }

        _ = linkInfoSize
        return bottleExecutableURL(fromWindowsPath: windowsPath, bottleDirectory: bottleDirectory)
    }

    private static func bottleExecutableURL(fromWindowsPath windowsPath: String, bottleDirectory: URL) -> URL? {
        var normalized = windowsPath.replacingOccurrences(of: "\\", with: "/")
        guard normalized.lowercased().hasSuffix(".exe") else { return nil }

        if normalized.count >= 2 && normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" {
            let drivePrefix = String(normalized.prefix(2))
            let pathTail = String(normalized.dropFirst(2))
            if drivePrefix.lowercased() == "c:" {
                normalized = bottleDirectory
                    .appending(path: "drive_c")
                    .appending(path: pathTail.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                    .path(percentEncoded: false)
            }
        }

        return URL(fileURLWithPath: normalized)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return data[offset..<(offset + 2)].withUnsafeBytes { pointer in
            pointer.loadUnaligned(as: UInt16.self)
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return data[offset..<(offset + 4)].withUnsafeBytes { pointer in
            pointer.loadUnaligned(as: UInt32.self)
        }
    }

    private static func readASCIICString(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let tail = data[offset...]
        guard let nul = tail.firstIndex(of: 0) else { return nil }
        return String(data: data[offset..<nul], encoding: .utf8)
    }

    private static func readUTF16CString(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }

        var cursor = offset
        while cursor + 1 < data.count {
            if data[cursor] == 0 && data[cursor + 1] == 0 {
                break
            }
            cursor += 2
        }

        guard cursor > offset else { return nil }
        return String(data: data[offset..<cursor], encoding: .utf16LittleEndian)
    }
}

