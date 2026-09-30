import Foundation

/// Resolves resources without initializing SwiftPM's trapping Bundle.module accessor.
/// Release packaging puts the resource bundle in Contents/Resources; SwiftPM puts
/// it beside the executable. Neither layout should depend on the build machine.
struct RuntimeResources: Sendable {
    static let bundleName = "Scotch_ScotchRuntime.bundle"
    static let bundled = RuntimeResources(
        resourceURL: Bundle.main.resourceURL,
        executableURL: Bundle.main.executableURL
    )

    private let directories: [URL]

    init(resourceURL: URL?, executableURL: URL?) {
        var roots = resourceURL.map { [$0] } ?? []
        if let executableURL {
            let executableDirectory = executableURL.deletingLastPathComponent()
            roots.append(executableDirectory)

            // Includes the containing app when running from its QuickLook extension.
            var ancestor = executableDirectory
            while ancestor.path != "/" {
                if ancestor.lastPathComponent == "Contents" {
                    roots.append(ancestor.appending(path: "Resources"))
                }
                if ancestor.pathExtension == "xctest" {
                    roots.append(ancestor.deletingLastPathComponent())
                }
                ancestor.deleteLastPathComponent()
            }
        }
        directories = roots.map { $0.appending(path: Self.bundleName) }
    }

    func url(forResource name: String, withExtension extensionName: String?, subdirectory: String? = nil) -> URL? {
        let fileName = extensionName.map { "\(name).\($0)" } ?? name
        for directory in directories {
            // .process("Resources") flattens ordinary files; also support preserved folders.
            var candidates: [URL] = []
            if let subdirectory {
                candidates.append(directory.appending(path: subdirectory).appending(path: fileName))
            }
            candidates.append(directory.appending(path: fileName))
            for candidate in candidates {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return nil
    }
}
