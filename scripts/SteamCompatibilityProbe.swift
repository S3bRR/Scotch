import Foundation

@main struct SteamCompatibilityProbe {
    static func main() throws {
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try condition() else { throw NSError(domain: "SteamCompatibilityProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let steam = URL(fileURLWithPath: "/Games/Steam/Steam.exe")
        let game = URL(fileURLWithPath: "/Games/game.exe")
        let gameArguments = ["-applaunch", "123", "-shutdown", "-cef-disable-gpu"]
        let launch = SteamLaunchPolicy.applying(to: gameArguments, executable: steam)
        try check(launch == SteamLaunchPolicy.arguments + gameArguments, "Client/game arguments changed")
        try check(Array(launch.suffix(gameArguments.count)) == gameArguments, "Game arguments changed")
        try check(SteamLaunchPolicy.applying(to: ["-shutdown"], executable: steam) == ["-shutdown"], "Shutdown became a UI launch")
        try check(SteamLaunchPolicy.applying(to: ["--test"], executable: game) == ["--test"], "A game's rendering options changed")
        try check(Array(launch.prefix(SteamLaunchPolicy.arguments.count)) == ["-cef-disable-sandbox"], "Driver repair unexpectedly added a GPU switch")
        try check(SteamLaunchPolicy.applying(to: [], executable: steam, usingMetalEngine: true) == SteamLaunchPolicy.arguments, "CEF compatibility switch was not applied")
        try check(SteamLaunchPolicy.applying(to: ["--test"], executable: game, usingMetalEngine: true) == ["--test"], "Steam's sandbox option leaked into game arguments")
        let deduplicated = SteamLaunchPolicy.applying(to: ["-CEF-DISABLE-GPU"], executable: steam)
        try check(deduplicated.filter { $0.lowercased() == "-cef-disable-gpu" }.count == 1, "Duplicate client option")
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchSteamMigration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cef = root.appending(path: "bin/cef/cef.win64")
        try FileManager.default.createDirectory(at: cef, withIntermediateDirectories: true)
        let helper = cef.appending(path: "steamwebhelper.exe")
        let real = cef.appending(path: "steamwebhelper_real.exe")
        let shim = Data("MZ old Scotch launcher".utf8)
        let original = Data("MZ Valve helper original".utf8)
        let updated = Data("MZ Valve helper updated".utf8)
        let migration = SteamWebHelperLauncher(launcher: shim)
        try original.write(to: helper)
        try migration.restoreOriginalIfNeeded(steamDirectory: root)
        try check(try Data(contentsOf: helper) == original, "Unmodified vendor helper changed")
        var padded = shim; padded.append(Data(count: 100))
        try padded.write(to: helper); try original.write(to: real)
        try migration.restoreOriginalIfNeeded(steamDirectory: root)
        try check(try Data(contentsOf: helper) == original, "Legacy helper was not restored")
        try check(try Data(contentsOf: real) == original, "Recovery backup was lost")
        try updated.write(to: helper)
        try migration.restoreOriginalIfNeeded(steamDirectory: root)
        try check(try Data(contentsOf: helper) == updated, "Steam's new helper was overwritten by an old backup")
        try padded.write(to: helper); try FileManager.default.removeItem(at: real)
        try migration.restoreOriginalIfNeeded(steamDirectory: root)
        try check(!FileManager.default.fileExists(atPath: helper.path), "Bootstrap cannot restore the missing vendor helper")
        let retained = try FileManager.default.contentsOfDirectory(at: cef, includingPropertiesForKeys: nil)
        try check(retained.count == 1, "Missing-original migration did not retain its obsolete shim")
        try check(try Data(contentsOf: retained[0]) == padded, "The only remaining helper copy was deleted")
        print("Passed: Steam/game argument separation, shutdown, untouched vendor updates, legacy restoration, and retained recovery copies")
    }
}
