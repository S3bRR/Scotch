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

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>launch</string>
            <key>CFBundleName</key>
            <string>\(program.displayName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>LSMinimumSystemVersion</key>
            <string>14.0</string>
            <key>LSApplicationCategoryType</key>
            <string>public.app-category.games</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsURL.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
    }
}
