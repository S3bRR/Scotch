import Foundation

extension PEFile {
    public struct COFFFileHeader: Hashable, Equatable, Sendable {
        public let machine: UInt16
        public let numberOfSections: UInt16
        public let timeDateStamp: Date
        public let pointerToSymbolTable: UInt32
        public let numberOfSymbols: UInt32
        public let sizeOfOptionalHeader: UInt16
        public let characteristics: UInt16

        init(handle: FileHandle, offset: UInt64) {
            var offset = offset + 4

            self.machine = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2

            self.numberOfSections = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2

            let timeDateStamp = handle.extract(UInt32.self, offset: offset) ?? 0
            self.timeDateStamp = Date(timeIntervalSince1970: TimeInterval(timeDateStamp))
            offset += 4

            self.pointerToSymbolTable = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4

            self.numberOfSymbols = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4

            self.sizeOfOptionalHeader = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2

            self.characteristics = handle.extract(UInt16.self, offset: offset) ?? 0
            offset += 2
        }
    }
}
