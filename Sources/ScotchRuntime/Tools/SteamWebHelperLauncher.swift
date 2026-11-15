import Foundation

/// Migration for the old padded Steam CEF launcher. Bootstrap and updates can
/// replace its helper after our launch check, so use Steam's own client flags.
/// Keep the bundled old launcher only to recognize and recover our own files.
struct SteamWebHelperLauncher: Sendable {
    let launcher: Data

    static func bundled() -> SteamWebHelperLauncher? {
        guard let url = RuntimeResources.bundled.url(
            forResource: "steamwebhelper_launcher", withExtension: "exe", subdirectory: "SteamWebHelper"
        ), let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return SteamWebHelperLauncher(launcher: data)
    }

    private func helper(in steamDirectory: URL) -> URL {
        steamDirectory.appending(path: "bin/cef/cef.win64/steamwebhelper.exe")
    }

    func needsRestoration(steamDirectory: URL) throws -> Bool {
        let file = helper(in: steamDirectory)
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        return try Data(contentsOf: file, options: .mappedIfSafe).starts(with: launcher)
    }

    func restoreOriginalIfNeeded(steamDirectory: URL) throws {
        guard try needsRestoration(steamDirectory: steamDirectory) else { return }
        let file = helper(in: steamDirectory)
        let original = file.deletingLastPathComponent().appending(path: "steamwebhelper_real.exe")
        let fm = FileManager.default
        if fm.fileExists(atPath: original.path) {
            let data = try Data(contentsOf: original, options: .mappedIfSafe)
            guard data.starts(with: [0x4d, 0x5a]), !data.starts(with: launcher) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // Atomic replacement; retain the original backup for recovery.
            try data.write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } else {
            // Missing vendor executable makes Steam's own bootstrapper restore
            // it. Retain the obsolete shim instead of destroying the only copy.
            let backup = file.deletingLastPathComponent().appending(path: "steamwebhelper-scotch-legacy-\(UUID().uuidString).exe")
            try fm.moveItem(at: file, to: backup)
        }
    }
}
