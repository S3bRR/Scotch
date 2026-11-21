import Foundation

extension PEFile {
    public enum Magic: UInt16, Hashable, Equatable, CustomStringConvertible, Sendable {
        case unknown = 0x0
        case pe32 = 0x10b
        case pe32Plus = 0x20b

        public var description: String {
            switch self {
            case .unknown:
                return "unknown"
            case .pe32:
                return "PE32"
            case .pe32Plus:
                return "PE32+"
            }
        }
    }
}
