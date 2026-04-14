import Foundation
import ScotchDomain

public struct AppPaths: Sendable {
    public let bundleIdentifier: String
    public let applicationSupportDirectory: URL
    public let containerDirectory: URL
    public let logsDirectory: URL

    public var librariesDirectory: URL {
        applicationSupportDirectory.appending(path: "Libraries")
    }

    public var runtimeManifestURL: URL {
        librariesDirectory.appending(path: RuntimeManifest.fileName)
    }

    public var bottleCatalogURL: URL {
        containerDirectory.appending(path: BottleCatalog.fileName)
    }

    public var alternateBottleCatalogURL: URL {
        containerDirectory.appending(path: BottleCatalog.alternateFileName)
    }

    public var settingsURL: URL {
        containerDirectory.appending(path: AppSettings.fileName)
    }

    public var defaultBottlesDirectory: URL {
        containerDirectory.appending(path: "Bottles")
    }

    public var wineBundleURL: URL {
        librariesDirectory.appending(path: "Wine.app")
    }

    public var wineBinaryURL: URL {
        librariesDirectory.appending(path: "Wine/bin/wine")
    }

    public var wineServerBinaryURL: URL {
        librariesDirectory.appending(path: "Wine/bin/wineserver")
    }

    public var runtimeBinDirectory: URL {
        librariesDirectory.appending(path: "Wine/bin")
    }

    public var winetricksScriptURL: URL {
        librariesDirectory.appending(path: "winetricks")
    }

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.s3brr.Scotch") {
        self.bundleIdentifier = bundleIdentifier
        self.applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleIdentifier)
        self.containerDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")
            .appending(path: bundleIdentifier)
        self.logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs")
            .appending(path: bundleIdentifier)
    }
}
