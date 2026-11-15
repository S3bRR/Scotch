import Foundation
import ScotchDomain
import ScotchInfrastructure

struct TarArchive {
    static func extract(_ archive: URL, to destination: URL, using runner: ProcessRunner, members: [String] = []) async throws {
        if !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        // bsdtar's default extraction rejects writes through escaping symlinks.
        // Reject absolute/traversal paths and escaping link targets before extraction too.
        let listing = try await runner.captureProcess(ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], displayName: "Inspect archive"), outputFileHandle: nil)
        for raw in listing.split(separator: "\n") {
            let name = String(raw)
            guard !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains("..") else {
                throw RuntimeInstallerError.extractionFailed("Unsafe archive path")
            }
        }
        let links = try await runner.captureProcess(ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tvf", archive.path], displayName: "Inspect archive links"), outputFileHandle: nil)
        for line in links.split(separator: "\n") {
            if let type = line.first, ["b", "c", "p", "s"].contains(String(type)) {
                throw RuntimeInstallerError.extractionFailed("Archive contains unsupported special files")
            }
            if let range = line.range(of: " -> ") {
                let target = String(line[range.upperBound...])
                // Conservative: relative links can point up within the archive, but
                // cannot require more parents than exist in the member's path.
                let before = String(line[..<range.lowerBound])
                let path = before.split(separator: " ").last.map(String.init) ?? ""
                let resolved = destination.appending(path: path).deletingLastPathComponent().appending(path: target).standardizedFileURL.path
                guard !target.hasPrefix("/"), resolved.hasPrefix(destination.standardizedFileURL.path + "/") else {
                    throw RuntimeInstallerError.extractionFailed("Archive symlink escapes the extraction directory")
                }
            }
        }
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xf", archive.path(percentEncoded: false), "-C", destination.path(percentEncoded: false)] + members,
            displayName: "tar -xf"
        )

        do {
            _ = try await runner.captureProcess(spec, outputFileHandle: nil)
        } catch let ProcessRunnerError.nonZeroExit(_, status, _) {
            throw RuntimeInstallerError.extractionFailed("tar returned \(status)")
        } catch {
            throw RuntimeInstallerError.extractionFailed("tar failed: \(error.localizedDescription)")
        }
    }
}
