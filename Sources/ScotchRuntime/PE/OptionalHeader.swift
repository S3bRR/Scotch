import Foundation

extension PEFile {
    public struct OptionalHeader: Hashable, Equatable, Sendable {
        public let magic: Magic
        public let majorLinkerVersion: UInt8
        public let minorLinkerVersion: UInt8
        public let sizeOfCode: UInt32
        public let sizeOfInitializedData: UInt32
        public let sizeOfUninitializedData: UInt32
        public let addressOfEntryPoint: UInt32
        public let baseOfCode: UInt32
        public let baseOfData: UInt32?

        public let imageBase: UInt64
        public let sectionAlignment: UInt32
        public let fileAlignment: UInt32

        init?(handle: FileHandle, offset: UInt64) {
            var offset = offset
            let rawMagic = handle.extract(UInt16.self, offset: offset) ?? 0
            let magic = Magic(rawValue: rawMagic) ?? .unknown
            self.magic = magic
            offset += 2
            self.majorLinkerVersion = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            self.minorLinkerVersion = handle.extract(UInt8.self, offset: offset) ?? 0
            offset += 1
            self.sizeOfCode = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfInitializedData = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.sizeOfUninitializedData = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.addressOfEntryPoint = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.baseOfCode = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4

            switch magic {
            case .pe32Plus:
                self.baseOfData = nil
                self.imageBase = handle.extract(UInt64.self, offset: offset) ?? 0
                offset += 8
            default:
                self.baseOfData = handle.extract(UInt32.self, offset: offset) ?? 0
                offset += 4
                let imageBase = handle.extract(UInt32.self, offset: offset) ?? 0
                self.imageBase = UInt64(imageBase)
                offset += 4
            }

            self.sectionAlignment = handle.extract(UInt32.self, offset: offset) ?? 0
            offset += 4
            self.fileAlignment = handle.extract(UInt32.self, offset: offset) ?? 0
        }
    }
}
