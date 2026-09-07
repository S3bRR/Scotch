import Foundation
import ScotchDomain

public actor GStreamerService: GStreamerServiceProtocol {
    private let frameworkPaths = [
        "/Library/Frameworks/GStreamer.framework",
        "/opt/local/Library/Frameworks/GStreamer.framework"
    ]

    public init() {}

    public func isInstalled() async -> Bool {
        frameworkPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
