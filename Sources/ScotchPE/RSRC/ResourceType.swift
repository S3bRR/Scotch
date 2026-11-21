import Foundation

public enum ResourceType: UInt32, CaseIterable, Hashable, Equatable {
    case unknown
    case icon = 3

    public init?(rawValue: UInt32?) {
        if let rawValue, let value = ResourceType(rawValue: rawValue) {
            self = value
        } else {
            self = .unknown
        }
    }
}
