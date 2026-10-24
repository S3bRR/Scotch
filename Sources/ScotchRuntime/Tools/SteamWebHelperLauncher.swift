import Foundation

/// Keeps Steam's UI from rendering as a black window under Wine 11 on Apple Silicon.
///
/// Steam's `steamwebhelper.exe` (Chromium) presents frames across processes, which
/// Wine's macOS driver drops. We swap it for a tiny launcher that starts the real
/// helper (renamed `steamwebhelper_real.exe`) with `--disable-gpu --single-process`.
/// Steam's startup check compares file sizes only, so the launcher is zero-padded
/// to the real helper's size; when a Steam update replaces the helper, the next
/// launch from Scotch wraps the new one.
struct SteamWebHelperLauncher: Sendable {
    enum Outcome: Equatable, Sendable {
        /// Steam isn't installed there, or has no 64-bit web helper.
        case notApplicable
        case alreadyInstalled
        /// Files changed; a running Steam must restart to pick them up.
        case installed
    }

    static let helperName = "steamwebhelper.exe"
    static let realHelperName = "steamwebhelper_real.exe"

    let launcher: Data

    static func bundled() -> SteamWebHelperLauncher? {
        guard let url = RuntimeResources.bundled.url(
            forResource: "steamwebhelper_launcher", withExtension: "exe", subdirectory: "SteamWebHelper"
        ), let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return SteamWebHelperLauncher(launcher: data)
    }

    func ensureInstalled(steamDirectory: URL) throws -> Outcome {
        let cefDirectory = steamDirectory.appending(path: "bin/cef/cef.win64")
        let helper = cefDirectory.appending(path: Self.helperName)
        let real = cefDirectory.appending(path: Self.realHelperName)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: helper.path) else {
            return .notApplicable
        }

        let current = try Data(contentsOf: helper, options: .mappedIfSafe)
        if current.starts(with: launcher) {
            if fileManager.fileExists(atPath: real.path) {
                return .alreadyInstalled
            }
            // Launcher with nothing to launch: remove it so Steam's own
            // verification restores the real helper on its next start.
            try fileManager.removeItem(at: helper)
            return .notApplicable
        }

        // `helper` is Steam's real binary (fresh install or updated by Steam).
        if fileManager.fileExists(atPath: real.path) {
            try fileManager.removeItem(at: real)
        }
        try fileManager.moveItem(at: helper, to: real)

        var replacement = launcher
        if current.count > replacement.count {
            replacement.append(Data(count: current.count - replacement.count))
        }
        do {
            try replacement.write(to: helper)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        } catch {
            try? fileManager.removeItem(at: helper)
            try? fileManager.moveItem(at: real, to: helper)
            throw error
        }
        return .installed
    }
}
