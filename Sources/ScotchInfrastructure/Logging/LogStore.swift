import Foundation
import ScotchDomain

public struct LogDestination: Sendable {
    public let fileHandle: FileHandle
    public let fileURL: URL

    public init(fileHandle: FileHandle, fileURL: URL) {
        self.fileHandle = fileHandle
        self.fileURL = fileURL
    }
}

public actor LogStore {
    private let logsDirectory: URL

    public init(logsDirectory: URL) {
        self.logsDirectory = logsDirectory
    }

    public func createLogFile(bottleID: BottleID? = nil) throws -> LogDestination {
        if !FileManager.default.fileExists(atPath: logsDirectory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let bottleComponent = bottleID.map { ".\($0.rawValue)" } ?? ""
        let fileURL = logsDirectory
            .appending(path: "\(timestamp)\(bottleComponent).\(UUID().uuidString)")
            .appendingPathExtension("log")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forWritingTo: fileURL)
        return LogDestination(fileHandle: handle, fileURL: fileURL)
    }

    public func recentLogs(limit: Int = 30) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
            .prefix(limit)
            .map { $0 }
    }

    public func recentLogs(for bottleID: BottleID, limit: Int = 30) -> [URL] {
        recentLogs(limit: 500)
            .filter { $0.lastPathComponent.contains(".\(bottleID.rawValue).") }
            .prefix(limit)
            .map { $0 }
    }

    public func readLog(at url: URL, maxCharacters: Int = 40000) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        if text.count <= maxCharacters {
            return text
        }
        return String(text.prefix(maxCharacters))
    }

    public func pruneLogs(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(TimeInterval(-(days * 24 * 60 * 60)))
        for item in recentLogs(limit: 500) {
            let created = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
            if created < cutoff {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}

public extension FileHandle {
    func writeLogHeader(appName: String, bundleIdentifier: String) {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let header = """
        App: \(appName)
        Bundle: \(bundleIdentifier)
        Date: \(ISO8601DateFormatter().string(from: Date()))
        macOS: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)

        """
        writeLine(header)
    }

    func writeBottleInfo(name: String, path: String, backend: String) {
        let content = """
        Bottle Name: \(name)
        Bottle Path: \(path)
        Backend: \(backend)

        """
        writeLine(content)
    }

    func writeLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            try write(contentsOf: data)
        } catch {
            return
        }
    }
}
