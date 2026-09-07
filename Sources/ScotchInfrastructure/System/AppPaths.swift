import Foundation
import ScotchDomain

public struct AppPaths: Sendable {
    public let bundleIdentifier: String
    public let applicationSupportDirectory: URL
    public let logsDirectory: URL
    public let legacyContainerDirectory: URL
    public let legacyLogsDirectory: URL
    public let preferencesURL: URL
    public let cachesDirectory: URL
    public let savedStateDirectory: URL

    public var librariesDirectory: URL {
        applicationSupportDirectory.appending(path: "Libraries")
    }

    public var runtimeManifestURL: URL {
        librariesDirectory.appending(path: RuntimeManifest.fileName)
    }

    public var bottleCatalogURL: URL {
        applicationSupportDirectory.appending(path: BottleCatalog.fileName)
    }

    public var alternateBottleCatalogURL: URL {
        applicationSupportDirectory.appending(path: BottleCatalog.alternateFileName)
    }

    public var settingsURL: URL {
        applicationSupportDirectory.appending(path: AppSettings.fileName)
    }

    public var installLedgerURL: URL {
        applicationSupportDirectory.appending(path: InstallLedger.fileName)
    }

    public var thumbnailContainerDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Containers")
            .appending(path: "\(bundleIdentifier).Thumbnail")
    }

    public var defaultBottlesDirectory: URL {
        applicationSupportDirectory.appending(path: "Bottles")
    }

    public var winetricksCacheDirectory: URL {
        applicationSupportDirectory.appending(path: "WinetricksCache")
    }

    public var launchEnvironmentDirectory: URL {
        applicationSupportDirectory.appending(path: "LaunchEnv")
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

    public var commandLineToolURL: URL {
        URL(fileURLWithPath: "/usr/local/bin/scotch")
    }

    public var gpuSpoofLogURL: URL {
        URL(fileURLWithPath: "/tmp/scotch_gpu_spoof.log")
    }

    public var catalogSearchURLs: [URL] {
        [
            bottleCatalogURL,
            alternateBottleCatalogURL,
            legacyContainerDirectory.appending(path: BottleCatalog.fileName),
            legacyContainerDirectory.appending(path: BottleCatalog.alternateFileName)
        ]
    }

    public var settingsSearchURLs: [URL] {
        [
            settingsURL,
            legacyContainerDirectory.appending(path: AppSettings.fileName)
        ]
    }

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.s3brr.Scotch") {
        self.bundleIdentifier = bundleIdentifier
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        self.applicationSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleIdentifier)
        self.logsDirectory = applicationSupportDirectory.appending(path: "Logs")
        self.legacyContainerDirectory = home
            .appending(path: "Library")
            .appending(path: "Containers")
            .appending(path: bundleIdentifier)
        self.legacyLogsDirectory = library
            .appending(path: "Logs")
            .appending(path: bundleIdentifier)
        self.preferencesURL = home
            .appending(path: "Library")
            .appending(path: "Preferences")
            .appending(path: "\(bundleIdentifier).plist")
        self.cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: bundleIdentifier)
        self.savedStateDirectory = home
            .appending(path: "Library")
            .appending(path: "Saved Application State")
            .appending(path: "\(bundleIdentifier).savedState")
    }
}
