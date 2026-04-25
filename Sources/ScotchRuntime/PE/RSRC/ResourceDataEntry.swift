import Foundation

public struct ResourceDataEntry: Hashable, Equatable {
    public let dataRVA: UInt32
    public let size: UInt32
    public let codePage: UInt32

    init?(handle: FileHandle, offset: UInt64) {
        var offset = offset
        self.dataRVA = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.size = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        self.codePage = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        let reserved = handle.extract(UInt32.self, offset: offset) ?? 0
        offset += 4
        guard reserved == 0 else { return nil }
    }

    public func resolveRVA(sections: [PEFile.Section]) -> UInt32? {
        sections
            .first { section in
                let mappedSize = max(section.virtualSize, section.sizeOfRawData)
                let (sectionEnd, overflow) = section.virtualAddress.addingReportingOverflow(mappedSize)
                return !overflow && section.virtualAddress <= dataRVA && dataRVA < sectionEnd
            }
            .map { section in
                let delta = dataRVA - section.virtualAddress
                let (resolved, overflow) = section.pointerToRawData.addingReportingOverflow(delta)
                return overflow ? nil : resolved
            }
            .flatMap { $0 }
    }
}
