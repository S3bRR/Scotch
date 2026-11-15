import AppKit
import Combine
import SwiftUI
import ScotchDomain
import ScotchFeatures
import ScotchInfrastructure
import Sparkle

/// One user action orchestrates both services. Sparkle owns authenticated app
/// replacement; the runtime service owns side-by-side runtime installation.
@MainActor
final class ScotchAppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var isPresented = false
    @Published private(set) var isWorking = false
    @Published fileprivate(set) var appStatus = "Not checked yet"
    @Published private(set) var runtimeStatus = "Not checked yet"
    @Published fileprivate(set) var progress: Double?
    private(set) var updater: SPUUpdater!
    private var driver: ScotchUpdateDriver!
    private let container: ScotchContainer
    private var appReply: ((SPUUserUpdateChoice) -> Void)?
    private var checkCompletion: CheckedContinuation<Void, Never>?
    private var task: Task<Void, Never>?
    private var installationLease: UpdateLease?
    private var cancelRequested = false
    private var started = false
    private var offeredBuild: Int?

    init(container: ScotchContainer) {
        self.container = container
        super.init()
        driver = ScotchUpdateDriver()
        driver.owner = self
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do { try updater.start(); started = true }
        catch { appStatus = error.localizedDescription }
        Task { [weak self] in
            guard let self else { return }
            let settings = await container.settingsStore.loadSettings()
            self.automaticallyChecks = settings.checkRuntimeUpdates
            let pendingURL = container.paths.applicationSupportDirectory.appending(path: "ResumeUpdate.plist")
            if let data = try? Data(contentsOf: pendingURL), let pending = try? PropertyListDecoder().decode([String: Int].self, from: data),
               let build = pending["build"], build <= (Int(ScotchAppInfo.build) ?? 0),
               let created = pending["created"], Date().timeIntervalSince1970 - Double(created) < 86_400 {
                try? FileManager.default.removeItem(at: pendingURL)
                self.update()
            }
        }
    }
    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
    func update() {
        isPresented = true
        guard !isWorking else { return }
        isWorking = true
        cancelRequested = false
        appStatus = "Checking Scotch \(ScotchAppInfo.version)…"
        runtimeStatus = "Checking approved runtime updates…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isWorking = false; self.progress = nil }
            let repairGraphics = await self.container.runtimeInstaller.needsGraphicsRepair()
            var runtime: ApprovedRuntimeSet?
            do {
                switch try await self.container.runtimeUpdates.check(force: true) {
                case .available(let target): runtime = target; self.runtimeStatus = "Available: \(target.title)"
                case .repair(let target): runtime = target; self.runtimeStatus = "Repairing missing or damaged files in \(target.title). Bottles are preserved."
                case .current: self.runtimeStatus = "No newer approved runtime available."
                case .incompatible(let message): self.runtimeStatus = message
                }
            } catch { self.runtimeStatus = "Runtime check: \(error.localizedDescription)" }
            if repairGraphics {
                self.runtimeStatus = "Graphics update available: D3DMetal 3.0, DXVK, DXMT 0.80, Mesa Zink 26.2, MoltenVK 1.4.2, and a compatible Wine 11.16 engine. Downloads use verified cached packages where available (up to 750 MB). Games and saves stay in place."
            }
            guard !Task.isCancelled else { return }
            if self.started && self.updater.canCheckForUpdates {
                await withCheckedContinuation { continuation in
                    self.checkCompletion = continuation
                    self.updater.checkForUpdates()
                }
            } else { self.appStatus = "An app update check is already in progress. Try Update again when it finishes." }
            guard !Task.isCancelled else { self.dismissOffer(); return }
            if let runtime {
                do { try await self.waitForIdle(component: "runtime") }
                catch { self.dismissOffer(); return }
                let components = runtime.packages.map { "\($0.component.rawValue): \($0.version)" }.joined(separator: ", ")
                self.runtimeStatus = "Installing \(runtime.title) — \(components). Existing bottles keep their working runtime."
                do {
                    try await self.container.runtimeUpdates.install(runtime)
                    self.runtimeStatus = "Installed \(runtime.title). New bottles use it; existing bottles can switch with a backup from Bottle Runtime."
                    NotificationCenter.default.post(name: .scotchBottleRuntimeChanged, object: nil)
                } catch { self.runtimeStatus = "Runtime update: \(error.localizedDescription)" }
            }
            guard !Task.isCancelled else { self.dismissOffer(); return }
            if repairGraphics {
                do {
                    try await self.waitForIdle(component: "runtime")
                    self.runtimeStatus = "Updating D3DMetal, DXVK, DXMT, Mesa Zink, MoltenVK, and the compatible Wine engine…"
                    try await self.container.runtimeInstaller.repairGraphics()
                    self.runtimeStatus = "Graphics updated: D3DMetal 3.0, DXVK, DXMT 0.80, Mesa Zink 26.2, MoltenVK 1.4.2, and the compatible Wine engine. Existing bottles, games, and saves are preserved."
                    NotificationCenter.default.post(name: .scotchBottleRuntimeChanged, object: nil)
                } catch {
                    self.runtimeStatus = "Graphics repair failed: \(error.localizedDescription). Existing runtime files are preserved."
                }
            }
            guard !Task.isCancelled else { self.dismissOffer(); return }
            if let reply = self.appReply {
                let path = Bundle.main.bundleURL
                guard !path.path.hasPrefix("/Volumes/"), FileManager.default.isWritableFile(atPath: path.deletingLastPathComponent().path) else {
                    self.appStatus = "Copy Scotch into Applications before updating the app."
                    self.dismissOffer()
                    return
                }
                do {
                    try await self.waitForIdle(component: "Scotch")
                    self.installationLease = try UpdateActivity.shared.acquireMaintenance()
                    try UpdateBackup.metadata(paths: self.container.paths)
                    // The new app can contain a newer bundled graphics profile, or
                    // understand runtime metadata this app cannot decode yet.
                    if let build = self.offeredBuild {
                        let pending = ["build": build, "created": Int(Date().timeIntervalSince1970)]
                        try PropertyListEncoder().encode(pending).write(to: self.container.paths.applicationSupportDirectory.appending(path: "ResumeUpdate.plist"), options: .atomic)
                    }
                    self.appReply = nil
                    self.appStatus = "Downloading Scotch. Bottles and settings will be preserved."
                    self.isWorking = true
                    reply(.install)
                    // Download/extraction/relaunch progress continues through the driver.
                    while self.installationLease != nil && !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
                } catch { self.appStatus = error.localizedDescription; self.installationLease = nil; self.dismissOffer() }
            }
        }
    }
    private func waitForIdle(component: String) async throws {
        while !Task.isCancelled {
            do {
                let lease = try UpdateActivity.shared.acquireMaintenance()
                withExtendedLifetime(lease) {}
                return
            } catch {
                let message = "Waiting to update \(component): \(error.localizedDescription)"
                if component == "runtime" { runtimeStatus = message } else { appStatus = message }
                try await Task.sleep(for: .seconds(3))
            }
        }
        throw CancellationError()
    }
    func cancel() {
        cancelRequested = true
        if installationLease == nil { task?.cancel() }
        driver.cancelDownload?()
        dismissOffer()
        completeCheck()
        if installationLease == nil { isWorking = false }
    }
    fileprivate func found(_ item: SUAppcastItem, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        NotificationCenter.default.post(name: .scotchUpdateAvailable, object: "Scotch \(item.displayVersionString) is available")
        offeredBuild = Int(item.versionString)
        appStatus = "Scotch \(ScotchAppInfo.version) → \(item.displayVersionString)"
        if isWorking { appReply = reply; completeCheck() }
        else { reply(.dismiss) }
    }
    fileprivate func completeCheck() { checkCompletion?.resume(); checkCompletion = nil }
    fileprivate func appError(_ error: Error) {
        appStatus = (error as NSError).code == SUError.noUpdateError.rawValue ? "No newer compatible Scotch release is available." : "Scotch update: \(error.localizedDescription)"
        if (error as NSError).code == SUError.noUpdateError.rawValue {
            NotificationCenter.default.post(name: .scotchUpdateAvailable, object: nil)
        }
        completeCheck()
        installationLease = nil
    }
    private func dismissOffer() { appReply?(.dismiss); appReply = nil }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Checks do not replace anything. Installation takes the exclusive lease.
        if UpdateActivity.shared.isApplyingUpdate { throw UpdateActivityError.busy("Another update is being installed.") }
    }
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Authenticated loopback fixtures exercise the real updater without publishing.
        if let raw = ProcessInfo.processInfo.environment["SCOTCH_UPDATE_TEST_FEED_URL"], let url = URL(string: raw), url.host == "127.0.0.1", url.scheme == "http" { return raw }
        return nil
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { appError(error) }
    fileprivate func ready(_ reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Task { [weak self] in
            guard let self else { reply(.skip); return }
            while UpdateActivity.shared.hasRunningWineProcesses && !self.cancelRequested {
                self.appStatus = "Waiting for games to close before restarting Scotch…"
                try? await Task.sleep(for: .seconds(3))
            }
            guard self.installationLease != nil, !self.cancelRequested else {
                reply(.skip)
                self.installationLease = nil
                self.appStatus = "App update canceled."
                return
            }
            self.appStatus = "Installing Scotch and restarting…"
            reply(.install)
        }
    }

}

@MainActor
private final class ScotchUpdateDriver: NSObject, SPUUserDriver {
    weak var owner: ScotchAppUpdater?
    var cancelDownload: (() -> Void)?
    private var expected: UInt64 = 0
    private var received: UInt64 = 0
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { cancelDownload = cancellation }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { owner?.found(appcastItem, reply: reply) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { owner?.appError(error); acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { owner?.appError(error); acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { cancelDownload = cancellation; received = 0 }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) { received += length; owner?.progress = expected > 0 ? min(Double(received) / Double(expected), 1) : nil }
    func showDownloadDidStartExtractingUpdate() { cancelDownload = nil; owner?.appStatus = "Verifying and extracting Scotch…"; owner?.progress = nil }
    func showExtractionReceivedProgress(_ progress: Double) { owner?.progress = progress }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { owner?.ready(reply) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { owner?.appStatus = "Installing Scotch and restarting…" }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { cancelDownload = nil }
}

struct ScotchUpdatesView: View {
    @ObservedObject var updater: ScotchAppUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Update").font(.title2.bold())
            Text("Scotch").font(.headline)
            Text(updater.appStatus).textSelection(.enabled)
            Divider()
            Text("Wine and graphics backends").font(.headline)
            Text(updater.runtimeStatus).textSelection(.enabled)
            if updater.isWorking {
                if let progress = updater.progress { ProgressView(value: progress) }
                else { ProgressView().controlSize(.small) }
            }
            Text("Update checks Scotch and the approved runtime together. Bottles, games, saves, and settings stay in place. Close games before installation. A recovery snapshot protects bottles that change Wine engines.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(updater.isWorking ? "Cancel" : "Close") {
                    if updater.isWorking { updater.cancel() } else { updater.isPresented = false }
                }
                Spacer()
            }
        }
        .padding(24).frame(width: 560).interactiveDismissDisabled(updater.isWorking)
    }
}
