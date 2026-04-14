import Foundation

public extension String {
    var shellEscaped: String {
        let characters = [
            "\\", "\"", "'", " ", "(", ")", "[", "]", "{", "}", "&", "|",
            ";", "<", ">", "`", "$", "!", "*", "?", "#", "~", "="
        ]

        var escaped = self
        for character in characters {
            escaped = escaped.replacingOccurrences(of: character, with: "\\" + character)
        }
        return escaped
    }
}

public extension URL {
    var shellEscapedPath: String {
        path(percentEncoded: false).shellEscaped
    }

    func userFacingPath(bundleIdentifier: String, userName: String = NSUserName()) -> String {
        path(percentEncoded: false)
            .replacingOccurrences(of: bundleIdentifier, with: "Scotch")
            .replacingOccurrences(of: "/Users/\(userName)", with: "~")
    }
}
