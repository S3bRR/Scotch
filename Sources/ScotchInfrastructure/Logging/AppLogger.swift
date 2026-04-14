import Foundation
import OSLog

public protocol AppLogger: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}

public struct DefaultAppLogger: AppLogger {
    private let logger: Logger

    public init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
