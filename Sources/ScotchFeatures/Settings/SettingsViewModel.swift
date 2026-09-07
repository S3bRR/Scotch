import Foundation
import ScotchDomain

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var runtimeManifest: RuntimeManifest?
    @Published public var statusMessage: String?
    @Published public var includeBottlesInUninstall = true
    @Published public var includeAppBundleInUninstall = true
    @Published public var uninstallPlan: UninstallPlan?
    @Published public var isUninstalling = false

    private let container: ScotchContainer

    public init(container: ScotchContainer, settings: AppSettings, runtimeManifest: RuntimeManifest?) {
        self.container = container
        self.settings = settings
        self.runtimeManifest = runtimeManifest
    }

    public func save(using persist: @MainActor (AppSettings) async -> Void) async {
        await persist(settings)
        statusMessage = "Saved settings."
    }

    public func refreshManifest() async {
        runtimeManifest = await container.runtimeInstaller.currentManifest()
    }

    public func refreshUninstallPreview() async {
        uninstallPlan = await container.uninstallService.preview(
            includeBottles: includeBottlesInUninstall,
            includeAppBundle: includeAppBundleInUninstall
        )
    }

    public func uninstallScotch() async -> Bool {
        isUninstalling = true
        defer { isUninstalling = false }

        let plan = await container.uninstallService.preview(
            includeBottles: includeBottlesInUninstall,
            includeAppBundle: includeAppBundleInUninstall
        )
        uninstallPlan = plan

        do {
            let result = try await container.uninstallService.perform(plan)
            if result.errors.isEmpty {
                statusMessage = "Scotch has been uninstalled."
                return true
            }
            statusMessage = "Uninstall finished with warnings: \(result.errors.joined(separator: "; "))"
            return result.scheduledAppBundleRemoval || result.removedPaths.contains(where: { $0.contains("Application Support") })
        } catch {
            statusMessage = "Uninstall failed: \(error.localizedDescription)"
            return false
        }
    }

    public var uninstallSummary: String {
        guard let plan = uninstallPlan else {
            return "Scotch will remove its runtime, settings, logs, caches, and the optional command-line tool."
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let size = formatter.string(fromByteCount: plan.totalByteCount)
        let count = plan.existingTargets.count
        return "\(count) item\(count == 1 ? "" : "s") totaling \(size) will be deleted."
    }
}
