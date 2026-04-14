import Foundation
import ScotchDomain
import ScotchInfrastructure

struct TarArchive {
    static func extract(_ archive: URL, to destination: URL, using runner: ProcessRunner) async throws {
        if !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xf", archive.path(percentEncoded: false), "-C", destination.path(percentEncoded: false)],
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
