import Foundation
import ScotchDomain

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var runtimeManifest: RuntimeManifest?
    @Published public var statusMessage: String?

    private let container: ScotchContainer

    public init(container: ScotchContainer, settings: AppSettings, runtimeManifest: RuntimeManifest?) {
        self.container = container
        self.settings = settings
        self.runtimeManifest = runtimeManifest
    }

    public func save() async {
        await container.settingsStore.saveSettings(settings)
        statusMessage = "Saved settings."
    }

    public func refreshManifest() async {
        runtimeManifest = await container.runtimeInstaller.currentManifest()
    }
}
