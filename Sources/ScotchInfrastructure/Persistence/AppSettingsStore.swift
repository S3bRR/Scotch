import Foundation
import ScotchDomain

public actor AppSettingsStore: AppSettingsStoreProtocol {
    private let store: PlistStore
    private let settingsURL: URL
    private let defaultBottleDirectory: URL

    public init(store: PlistStore, settingsURL: URL, defaultBottleDirectory: URL) {
        self.store = store
        self.settingsURL = settingsURL
        self.defaultBottleDirectory = defaultBottleDirectory
    }

    public func loadSettings() async -> AppSettings {
        do {
            var loaded = try await store.read(AppSettings.self, from: settingsURL)
            if loaded.defaultBottleDirectoryPath.isEmpty {
                loaded.defaultBottleDirectoryPath = defaultBottleDirectory.path(percentEncoded: false)
                try? await store.write(loaded, to: settingsURL)
            }
            return loaded
        } catch {
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
    }

    public func saveSettings(_ settings: AppSettings) async {
        try? await store.write(settings, to: settingsURL)
    }
}
