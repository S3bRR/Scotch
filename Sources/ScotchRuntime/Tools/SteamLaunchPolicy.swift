import Foundation

/// The matched engine fixes Steam's cross-process surfaces and routes its CEF
/// helper separately. GPU rendering stays enabled. The Wine engine still needs
/// Steam's CEF-only Windows sandbox compatibility switch.
enum SteamLaunchPolicy {
    static let arguments = ["-cef-disable-sandbox"]

    static func applying(to arguments: [String], executable: URL, usingMetalEngine: Bool = false) -> [String] {
        guard executable.lastPathComponent.caseInsensitiveCompare("steam.exe") == .orderedSame else { return arguments }
        let gameBoundary = arguments.firstIndex(where: { ["-applaunch", "-rungameid"].contains($0.lowercased()) }) ?? arguments.endIndex
        let clientArguments = arguments[..<gameBoundary]
        guard !clientArguments.contains(where: { $0.caseInsensitiveCompare("-shutdown") == .orderedSame }) else { return arguments }
        let required = Self.arguments
        return required.filter { flag in !clientArguments.contains(where: { $0.caseInsensitiveCompare(flag) == .orderedSame }) } + arguments
    }
}
