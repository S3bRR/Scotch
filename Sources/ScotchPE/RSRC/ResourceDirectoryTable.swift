import Foundation

public struct ResourceDirectoryTable: Hashable, Equatable {
    private static let maxDepth = 8

    public let characteristics: UInt32
    public let timeDateStamp: Date
    public let majorVersion: UInt16
    public let minorVersion: UInt16
    public let numberOfNameEntries: UInt16
    public let numberOfIdEntries: UInt16

    public let subtables: [ResourceDirectoryTable]
    public let entries: [ResourceDataEntry]

    private init() {
        self.characteristics = 0
        self.timeDateStamp = Date(timeIntervalSince1970: 0)
        self.majorVersion = 0
        self.minorVersion = 0
        self.numberOfNameEntries = 0
        self.numberOfIdEntries = 0
        self.subtables = []
        self.entries = []
    }

    init(handle: FileHandle, pointerToRawData: UInt64, types: [ResourceType]?, fileSize: UInt64) {
        var visited: Set<UInt64> = []
        self.init(
            handle: handle,
            pointerToRawData: pointerToRawData,
            offset: 0,
            types: types,
            fileSize: fileSize,
            depth: 0,
            visited: &visited
        )
    }

    init(
        handle: FileHandle,
        pointerToRawData: UInt64,
        offset initialOffset: UInt64,
        types: [ResourceType]? = nil,
        fileSize: UInt64,
        depth: Int,
        visited: inout Set<UInt64>
    ) {
        let (tableOffset, tableOverflow) = pointerToRawData.addingReportingOverflow(initialOffset)
        var parsedCharacteristics: UInt32 = 0
        var parsedTimeDateStamp = Date(timeIntervalSince1970: 0)
        var parsedMajorVersion: UInt16 = 0
        var parsedMinorVersion: UInt16 = 0
        var parsedNameEntries: UInt16 = 0
        var parsedIDEntries: UInt16 = 0
        var parsedSubtables: [ResourceDirectoryTable] = []
        var parsedEntries: [ResourceDataEntry] = []

        if !tableOverflow,
           depth <= Self.maxDepth,
           tableOffset + 16 <= fileSize,
           visited.insert(tableOffset).inserted {
            var offset = tableOffset
            parsedCharacteristics = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            let timeDateStamp = handle.extract(UInt32.self, offset: offset) ?? 0
            parsedTimeDateStamp = Date(timeIntervalSince1970: TimeInterval(timeDateStamp))
            offset += 4
            parsedMajorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            parsedMinorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            parsedNameEntries = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
            parsedIDEntries = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2

            let totalEntryCount = UInt64(parsedNameEntries) + UInt64(parsedIDEntries)
            if offset + (totalEntryCount * 8) <= fileSize {
                for _ in 0..<parsedNameEntries {
                    offset += 8
                }

                for _ in 0..<parsedIDEntries {
                    let directoryEntry = ResourceDirectoryEntry.ID(handle: handle, offset: offset)
                    offset += 8

                    if let types, !types.contains(directoryEntry.type) {
                        continue
                    }

                    if directoryEntry.isDirectory {
                        let subtable = ResourceDirectoryTable(
                            handle: handle,
                            pointerToRawData: pointerToRawData,
                            offset: UInt64(directoryEntry.offset),
                            fileSize: fileSize,
                            depth: depth + 1,
                            visited: &visited
                        )
                        parsedSubtables.append(subtable)
                    } else {
                        let (dataEntryOffset, overflow) = pointerToRawData.addingReportingOverflow(UInt64(directoryEntry.offset))
                        guard !overflow, dataEntryOffset + 16 <= fileSize else { continue }
                        if let entry = ResourceDataEntry(
                            handle: handle,
                            offset: dataEntryOffset
                        ) {
                            parsedEntries.append(entry)
                        }
                    }
                }
            }
        }

        self.characteristics = parsedCharacteristics
        self.timeDateStamp = parsedTimeDateStamp
        self.majorVersion = parsedMajorVersion
        self.minorVersion = parsedMinorVersion
        self.numberOfNameEntries = parsedNameEntries
        self.numberOfIdEntries = parsedIDEntries
        self.subtables = parsedSubtables
        self.entries = parsedEntries
    }

    public var allEntries: [ResourceDataEntry] {
        var entries = self.entries
        for subtable in subtables {
            entries.append(contentsOf: subtable.allEntries)
        }
        return entries
    }
}
