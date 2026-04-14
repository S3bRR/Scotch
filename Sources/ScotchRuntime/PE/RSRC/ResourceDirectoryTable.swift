import Foundation

public struct ResourceDirectoryTable: Hashable, Equatable {
    public let characteristics: UInt32
    public let timeDateStamp: Date
    public let majorVersion: UInt16
    public let minorVersion: UInt16
    public let numberOfNameEntries: UInt16
    public let numberOfIdEntries: UInt16

    public let subtables: [ResourceDirectoryTable]
    public let entries: [ResourceDataEntry]

    init(handle: FileHandle, pointerToRawData: UInt64, types: [ResourceType]?) {
        self.init(handle: handle, pointerToRawData: pointerToRawData, offset: 0, types: types)
    }

    init(
        handle: FileHandle,
        pointerToRawData: UInt64,
        offset initialOffset: UInt64,
        types: [ResourceType]? = nil
    ) {
        var offset = pointerToRawData + initialOffset
        self.characteristics = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        let timeDateStamp = handle.extract(UInt32.self, offset: offset) ?? 0
        self.timeDateStamp = Date(timeIntervalSince1970: TimeInterval(timeDateStamp))
        offset += 4
        self.majorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        self.minorVersion = handle.extract(UInt16.self, offset: offset) ?? 0
        offset += 2
        let numberOfNameEntries = handle.extract(UInt16.self, offset: offset) ?? 0
        self.numberOfNameEntries = numberOfNameEntries
        offset += 2
        let numberOfIdEntries = handle.extract(UInt16.self, offset: offset) ?? 0
        self.numberOfIdEntries = numberOfIdEntries
        offset += 2

        var subtables: [ResourceDirectoryTable] = []
        var entries: [ResourceDataEntry] = []

        for _ in 0..<numberOfNameEntries {
            offset += 8
        }

        for _ in 0..<numberOfIdEntries {
            let directoryEntry = ResourceDirectoryEntry.ID(handle: handle, offset: offset)
            offset += 8

            if let types {
                guard types.contains(directoryEntry.type) else { continue }
            }

            if directoryEntry.isDirectory {
                let subtable = ResourceDirectoryTable(
                    handle: handle,
                    pointerToRawData: pointerToRawData,
                    offset: UInt64(directoryEntry.offset)
                )
                subtables.append(subtable)
            } else if let entry = ResourceDataEntry(
                handle: handle,
                offset: pointerToRawData + UInt64(directoryEntry.offset)
            ) {
                entries.append(entry)
            }
        }

        self.subtables = subtables
        self.entries = entries
    }

    public var allEntries: [ResourceDataEntry] {
        var entries = self.entries
        for subtable in subtables {
            entries.append(contentsOf: subtable.allEntries)
        }
        return entries
    }
}
