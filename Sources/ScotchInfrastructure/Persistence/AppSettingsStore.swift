import Foundation
import ScotchDomain

public actor AppSettingsStore: AppSettingsStoreProtocol {
    private let store: PlistStore
    private let settingsURL: URL
    private let searchURLs: [URL]
    private let defaultBottleDirectory: URL

    public init(store: PlistStore, settingsURL: URL, defaultBottleDirectory: URL, searchURLs: [URL] = []) {
        self.store = store
        self.settingsURL = settingsURL
        self.searchURLs = searchURLs.isEmpty ? [settingsURL] : searchURLs
        self.defaultBottleDirectory = defaultBottleDirectory
    }

    public func loadSettings() async -> AppSettings {
        for url in searchURLs {
            if let loaded = try? await store.read(AppSettings.self, from: url) {
                var normalized = loaded
                if normalized.defaultBottleDirectoryPath.isEmpty {
                    normalized.defaultBottleDirectoryPath = defaultBottleDirectory.path(percentEncoded: false)
                }
                if url != settingsURL || normalized != loaded {
                    try? await store.write(normalized, to: settingsURL)
                }
                return normalized
            }
        }

        let defaults = UserDefaults.standard
        let initial = AppSettings(
            killProcessesOnTerminate: defaults.object(forKey: AppSettings.legacyKillOnTerminateDefaultsKey) as? Bool ?? true,
            checkRuntimeUpdates: defaults.object(forKey: AppSettings.legacyRuntimeUpdatesDefaultsKey) as? Bool ?? true,
            defaultBottleDirectoryPath: defaults.string(forKey: AppSettings.legacyDefaultBottleLocationDefaultsKey)
                ?? defaultBottleDirectory.path(percentEncoded: false)
        )
        try? await store.write(initial, to: settingsURL)
        return initial
    }

    public func saveSettings(_ settings: AppSettings) async {
        try? await store.write(settings, to: settingsURL)
    }
}
