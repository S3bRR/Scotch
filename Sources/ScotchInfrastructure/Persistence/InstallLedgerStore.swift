import Foundation
import ScotchDomain

public actor InstallLedgerStore: InstallLedgerProtocol {
    private let paths: AppPaths
    private let store: PlistStore

    public init(paths: AppPaths, store: PlistStore) {
        self.paths = paths
        self.store = store
    }

    public func record(path: URL, kind: UninstallTarget.Kind, note: String? = nil) async {
        var ledger = await load()
        let normalized = URL(fileURLWithPath: path.path(percentEncoded: false)).path(percentEncoded: false)
        if let index = ledger.entries.firstIndex(where: { $0.path == normalized }) {
            ledger.entries[index].kind = kind
            if let note {
                ledger.entries[index].note = note
            }
        } else {
            ledger.entries.append(
                InstallLedgerEntry(path: normalized, kind: kind, note: note)
            )
        }
        ledger.entries = InstallLedger.deduplicated(ledger.entries)
        try? await store.write(ledger, to: paths.installLedgerURL)
    }

    public func entries() async -> [InstallLedgerEntry] {
        await load().entries
    }

    public func seedKnownRoots() async {
        let roots: [(URL, UninstallTarget.Kind, String)] = [
            (paths.applicationSupportDirectory, .runtime, "Primary Scotch data root"),
            (paths.librariesDirectory, .runtime, "Wine and translation backends"),
            (paths.logsDirectory, .logs, "Launch logs"),
            (paths.defaultBottlesDirectory, .bottle, "Default bottle directory"),
            (paths.winetricksCacheDirectory, .cache, "Winetricks downloads"),
            (paths.launchEnvironmentDirectory, .temporary, "Per-bottle Wine launch env files"),
            (paths.settingsURL, .settings, "App settings"),
            (paths.bottleCatalogURL, .settings, "Bottle catalog"),
            (paths.commandLineToolURL, .cli, "CLI symlink"),
            (paths.gpuSpoofLogURL, .temporary, "GPU spoof debug log"),
            (paths.legacyContainerDirectory, .leftover, "Pre-1.1.0 data root"),
            (paths.legacyLogsDirectory, .leftover, "Pre-1.1.0 logs"),
            (paths.cachesDirectory, .cache, "URLSession / app cache"),
            (paths.savedStateDirectory, .leftover, "Saved window state"),
            (paths.preferencesURL, .preferences, "UserDefaults plist"),
            (paths.thumbnailContainerDirectory, .leftover, "QuickLook thumbnail sandbox"),
            (paths.thumbnailApplicationScriptsDirectory, .leftover, "QuickLook application scripts"),
            (paths.commandCacheDirectory, .cache, "ScotchCmd URL/cache"),
            (paths.commandHTTPStorageDirectory, .cache, "ScotchCmd HTTP storage"),
            (paths.appHTTPStorageDirectory, .cache, "App HTTP storage"),
            (FileManager.default.temporaryDirectory.appending(path: "ScotchRuntimeDownloads"), .temporary, "Runtime archives"),
            (FileManager.default.temporaryDirectory.appending(path: "ScotchOverlays"), .temporary, "Overlay archives"),
            (FileManager.default.temporaryDirectory.appending(path: "ScotchSteamInstall"), .temporary, "Steam installer temp"),
            (FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cache/winetricks"), .cache, "Legacy winetricks cache")
        ]

        for (url, kind, note) in roots {
            await record(path: url, kind: kind, note: note)
        }

        if let appBundle = Bundle.main.bundleURL as URL?, appBundle.pathExtension == "app" {
            await record(path: appBundle, kind: .appBundle, note: "Running Scotch.app")
        }
    }

    private func load() async -> InstallLedger {
        (try? await store.read(InstallLedger.self, from: paths.installLedgerURL)) ?? InstallLedger()
    }
}
