import Foundation
import AppKit

enum CLIInstallError: LocalizedError {
    case missingExecutable
    case scriptCreationFailed
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Unable to locate ScotchCmd executable in this build."
        case .scriptCreationFailed:
            return "Failed to prepare privileged install script."
        case .scriptFailed(let message):
            return "Install failed: \(message)"
        }
    }
}

enum CommandLineInstaller {
    static let symlinkPath = "/usr/local/bin/scotch"

    static func install() async -> Result<Void, CLIInstallError> {
        guard let sourceURL = locateCmdExecutable() else {
            return .failure(.missingExecutable)
        }

        let escapedSource = sourceURL.path(percentEncoded: false)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        do shell script "mkdir -p /usr/local/bin && ln -fs \\"\(escapedSource)\\" \(symlinkPath)" with administrator privileges
        """

        var scriptError: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return .failure(.scriptCreationFailed)
        }

        appleScript.executeAndReturnError(&scriptError)

        if let scriptError {
            let description = (scriptError["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
            if description.localizedCaseInsensitiveContains("cancel") {
                return .success(())
            }
            return .failure(.scriptFailed(description))
        }
        return .success(())
    }

    private static func locateCmdExecutable() -> URL? {
        guard let mainExecutable = Bundle.main.executableURL else {
            return nil
        }

        let candidates = [
            mainExecutable.deletingLastPathComponent().appending(path: "ScotchCmd"),
            mainExecutable.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Helpers/ScotchCmd"),
            URL(fileURLWithPath: "/Applications/Scotch.app/Contents/MacOS/ScotchCmd")
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }
        return nil
    }
}
