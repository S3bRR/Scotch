import Foundation
import AppKit

public struct PEError: Error {
    public let message: String

    static let invalidPEFile = PEError(message: "Invalid PE file")
}

public enum PEArchitecture: Hashable, Sendable {
    case x32
    case x64
    case unknown

    public var displayName: String? {
        switch self {
        case .x32:
            "32-bit"
        case .x64:
            "64-bit"
        case .unknown:
            nil
        }
    }
}

/// Microsoft Portable Executable parser for extracting executable metadata and icons.
public struct PEFile: Hashable, Equatable, Sendable {
    public let url: URL
    public let coffFileHeader: COFFFileHeader
    public let optionalHeader: OptionalHeader?
    public let sections: [Section]
    public let fileSize: UInt64

    public init?(url: URL?) throws {
        guard let url else { return nil }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        self.url = url

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        self.fileSize = fileSize
        guard fileSize >= 0x40 else {
            throw PEError.invalidPEFile
        }

        guard let peOffset = handle.extract(UInt32.self, offset: 0x3C) else {
            throw PEError.invalidPEFile
        }

        var offset = UInt64(peOffset)
        guard offset + 24 <= fileSize else {
            throw PEError.invalidPEFile
        }
        guard let peHeader = handle.extract(UInt32.self, offset: offset) else {
            throw PEError.invalidPEFile
        }

        // Check signature ("PE\0\0")
        guard peHeader.bigEndian == 0x50450000 else {
            throw PEError.invalidPEFile
        }

        let coff = COFFFileHeader(handle: handle, offset: offset)
        self.coffFileHeader = coff
        offset += 24 // PE signature + COFF header size.

        if coff.sizeOfOptionalHeader > 0 {
            guard offset + UInt64(coff.sizeOfOptionalHeader) <= fileSize else {
                throw PEError.invalidPEFile
            }
            self.optionalHeader = OptionalHeader(handle: handle, offset: offset)
            offset += UInt64(coff.sizeOfOptionalHeader)
        } else {
            self.optionalHeader = nil
        }

        guard offset + (UInt64(coff.numberOfSections) * 40) <= fileSize else {
            throw PEError.invalidPEFile
        }

        var parsedSections: [Section] = []
        for _ in 0..<coff.numberOfSections {
            guard let section = Section(handle: handle, offset: offset) else {
                throw PEError.invalidPEFile
            }
            parsedSections.append(section)
            offset += 40 // section header size
        }
        self.sections = parsedSections
    }

    public var architecture: PEArchitecture {
        switch optionalHeader?.magic {
        case .pe32:
            .x32
        case .pe32Plus:
            .x64
        default:
            .unknown
        }
    }

    public var resourceDirectory: ResourceDirectoryTable? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        return readResourceDirectory(handle: handle)
    }

    /// Attempts to render the largest icon present in the PE resource directory.
    public func bestIcon() -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let resources = readResourceDirectory(handle: handle, types: [.icon]) else {
            return nil
        }

        let icons = resources.allEntries.compactMap { entry -> NSImage? in
            guard let offset = entry.resolveRVA(sections: sections) else { return nil }
            guard UInt64(offset) + UInt64(entry.size) <= fileSize else { return nil }
            let bitmapInfo = BitmapInfoHeader(handle: handle, offset: UInt64(offset))

            // Non-BITMAPINFOHEADER icon payloads can still decode via NSBitmapImageRep.
            if bitmapInfo.size != 40 {
                do {
                    try handle.seek(toOffset: UInt64(offset))
                    if let iconData = try handle.read(upToCount: Int(entry.size)),
                       let rep = NSBitmapImageRep(data: iconData) {
                        let image = NSImage(size: rep.size)
                        image.addRepresentation(rep)
                        return image
                    }
                } catch {
                    return nil
                }
            } else if bitmapInfo.colorFormat != .unknown {
                let bitmapDataStart = UInt64(offset) + UInt64(bitmapInfo.size)
                guard bitmapDataStart <= UInt64(offset) + UInt64(entry.size) else { return nil }
                return bitmapInfo.renderBitmap(
                    handle: handle,
                    offset: bitmapDataStart,
                    dataEnd: UInt64(offset) + UInt64(entry.size)
                )
            }

            return nil
        }
        .filter(\.isValid)

        return icons.max(by: { $0.size.height < $1.size.height })
    }

    private func readResourceDirectory(handle: FileHandle, types: [ResourceType] = ResourceType.allCases) -> ResourceDirectoryTable? {
        guard let resourceSection = sections.first(where: { $0.name == ".rsrc" }) else {
            return nil
        }

        return ResourceDirectoryTable(
            handle: handle,
            pointerToRawData: UInt64(resourceSection.pointerToRawData),
            types: types,
            fileSize: fileSize
        )
    }
}
