import Foundation
import ScotchDomain

public actor ShortcutService {
    public init() {}

    public func createShortcut(
        for program: ProgramRecord,
        in bottle: BottleSummary,
        destinationAppURL: URL,
        launchCommand: String
    ) throws {
        let contentsURL = destinationAppURL.appending(path: "Contents")
        let macOSURL = contentsURL.appending(path: "MacOS")
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let scriptURL = macOSURL.appending(path: "launch")
        let script = """
        #!/bin/bash
        \(launchCommand)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path(percentEncoded: false))

        let infoPlist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleName": program.displayName,
            "CFBundlePackageType": "APPL",
            "LSMinimumSystemVersion": "26.0",
            "LSApplicationCategoryType": "public.app-category.games"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"), options: .atomic)
    }
}
