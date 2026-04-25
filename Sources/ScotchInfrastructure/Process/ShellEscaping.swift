import Foundation

public extension String {
    var shellQuoted: String {
        guard !isEmpty else { return "''" }
        return "'\(replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    var shellEscaped: String {
        shellQuoted
    }

    var isShellEnvironmentKey: Bool {
        guard let first = unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        return unicodeScalars.allSatisfy { scalar in
            scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
    }
}

public extension URL {
    var shellEscapedPath: String {
        path(percentEncoded: false).shellQuoted
    }

    func userFacingPath(bundleIdentifier: String, userName: String = NSUserName()) -> String {
        path(percentEncoded: false)
            .replacingOccurrences(of: bundleIdentifier, with: "Scotch")
            .replacingOccurrences(of: "/Users/\(userName)", with: "~")
    }
}
