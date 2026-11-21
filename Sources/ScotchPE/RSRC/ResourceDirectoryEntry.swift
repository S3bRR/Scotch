import Foundation

public enum ResourceDirectoryEntry {
    public struct ID {
        public let type: ResourceType
        private let rawOffset: UInt32

        init(handle: FileHandle, offset: UInt64) {
            var offset = offset
            let rawType = handle.extract(UInt32.self, offset: offset) ?? 0
            self.type = ResourceType(rawValue: rawType) ?? .unknown
            offset += 4
            self.rawOffset = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
        }

        var isDirectory: Bool {
            (rawOffset & 0x80000000) != 0
        }

        var offset: UInt32 {
            if isDirectory {
                return rawOffset & 0x7FFFFFFF
            } else {
                return rawOffset
            }
        }
    }
}
