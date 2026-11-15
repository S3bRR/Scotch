import Foundation
import ScotchDomain
import ScotchInfrastructure

/// Shortcuts resolve the saved application profile at launch time, rather than
/// freezing the DLLs/environment that happened to be selected when created.
public enum ProgramLaunchCommand {
    public static func configured(executable: URL, bottle: BottleSummary) throws -> String {
        let command = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL.appending(path: "Contents/MacOS/ScotchCmd")
            : Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "ScotchCmd")
        guard let command, FileManager.default.isExecutableFile(atPath: command.path) else {
            throw RuntimeInstallerError.installFailed("Create configured shortcuts or terminal launches from an installed Scotch.app.")
        }
        return [command.path, "run-configured-path", bottle.directoryURL.path, executable.path].map(\.shellQuoted).joined(separator: " ")
    }
}
