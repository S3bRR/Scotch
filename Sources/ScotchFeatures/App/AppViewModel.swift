import Foundation
import AppKit
import ScotchDomain
import ScotchInfrastructure

@MainActor
public final class AppViewModel: ObservableObject {
    public enum SetupStage: Equatable {
        case idle
        case checking
        case installingRosetta
        case checkingGStreamer
        case fetchingRuntime
        case downloadingRuntime(Double)
        case installingRuntime
        case ready
        case failed(String)
    }

    @Published public var bottles: [BottleSummary] = []
    @Published public var selectedBottleID: BottleID?
    @Published public var appSettings: AppSettings
    @Published public var runtimeManifest: RuntimeManifest?
    @Published public var setupStage: SetupStage = .idle
    @Published public var showSetupSheet: Bool = false
    @Published public var isBusy: Bool = false
    @Published public var toastMessage: String?
    @Published public var overlayDrifts: [OverlayDrift] = []
    @Published public var runtimeUpdateVersion: AppVersion?

    public let container: ScotchContainer

    public init(container: ScotchContainer) {
        self.container = container
        self.appSettings = AppSettings(defaultBottleDirectoryPath: container.paths.defaultBottlesDirectory.path(percentEncoded: false))
    }

    public func bootstrap() async {
        setupStage = .checking
        appSettings = await container.settingsStore.loadSettings()
        runtimeManifest = await container.runtimeInstaller.currentManifest()
        if appSettings.checkRuntimeUpdates {
            let update = await container.runtimeInstaller.shouldUpdateRuntime()
            runtimeUpdateVersion = update.0 ? update.1 : nil
            overlayDrifts = await container.runtimeInstaller.overlayDrifts()
        } else {
            runtimeUpdateVersion = nil
            overlayDrifts = []
        }
        await container.installLedger.seedKnownRoots()
        await container.logStore.pruneLogs(olderThan: 7)
        await refreshBottles()
        for bottle in bottles {
            await container.installLedger.record(
                path: bottle.directoryURL,
                kind: .bottle,
                note: "Bottle \(bottle.settings.info.name)"
            )
        }

        let rosettaInstalled = await container.rosettaService.isInstalled()
        let runtimeInstalled = await container.runtimeInstaller.isRuntimeInstalled()
        if !rosettaInstalled || !runtimeInstalled {
            showSetupSheet = true
            setupStage = .idle
        } else {
            setupStage = .ready
        }
    }

    public func refreshBottles() async {
        bottles = await container.bottleRepository.loadBottles()
        if bottles.contains(where: { !$0.isAvailable && $0.settings.info.name.contains("Corrupted Metadata") }) {
            toastMessage = "One or more bottles have corrupted metadata. Review Diagnostics -> Migration Report."
        }
        if selectedBottleID == nil {
            selectedBottleID = bottles.first?.id
        } else if !bottles.contains(where: { $0.id == selectedBottleID }) {
            selectedBottleID = bottles.first?.id
        }
    }

    public func createBottle(name: String, windowsVersion: WindowsVersion, location: URL? = nil) async {
        isBusy = true
        defer { isBusy = false }

        let resolvedLocation = location ?? URL(fileURLWithPath: appSettings.defaultBottleDirectoryPath)
        let inFlight: BottleSummary
        do {
            inFlight = try await container.bottleRepository.prepareBottle(
                name: name,
                windowsVersion: windowsVersion,
                containerURL: resolvedLocation
            )
        } catch {
            toastMessage = "Failed to create bottle: \(error.localizedDescription)"
            return
        }

        insertBottleSorted(inFlight)
        selectedBottleID = inFlight.id

        let targetID = inFlight.id
        let progressCallback: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                if let index = self.bottles.firstIndex(where: { $0.id == targetID }) {
                    self.bottles[index].setupProgress = fraction
                }
            }
        }

        do {
            let afterSetup = try await container.bottleRepository.setupWineEnvironment(inFlight, progress: progressCallback)
            if let index = bottles.firstIndex(where: { $0.id == targetID }) {
                bottles[index] = afterSetup
            }

            let final = try await container.bottleRepository.installBottleCoreFonts(afterSetup, progress: progressCallback)
            if let index = bottles.firstIndex(where: { $0.id == targetID }) {
                bottles[index] = final
            }
            bottles.sort { $0.settings.info.name.lowercased() < $1.settings.info.name.lowercased() }
            selectedBottleID = final.id
            await container.installLedger.record(
                path: final.directoryURL,
                kind: .bottle,
                note: "Bottle \(final.settings.info.name)"
            )
        } catch {
            await rollbackFailedBottleCreation(inFlight)
            markBottleCreationFailed(id: inFlight.id, message: error.localizedDescription)
            toastMessage = "Failed to create bottle: \(error.localizedDescription)"
        }
    }

    private func rollbackFailedBottleCreation(_ summary: BottleSummary) async {
        try? await container.bottleRepository.deleteBottle(id: summary.id, removeFiles: true)
        if container.fileSystem.fileExists(at: summary.directoryURL) {
            try? container.fileSystem.removeItem(at: summary.directoryURL)
        }
    }

    private func markBottleCreationFailed(id: BottleID, message: String) {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else { return }
        bottles[index].inFlight = false
        bottles[index].isAvailable = false
        bottles[index].setupProgress = 0
        bottles[index].setupErrorMessage = message
        if selectedBottleID == id {
            selectedBottleID = bottles.first(where: { $0.id != id && $0.isAvailable })?.id
        }
    }

    public func dismissFailedBottle(_ id: BottleID) {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else { return }
        guard bottles[index].setupErrorMessage != nil else { return }
        bottles.remove(at: index)
        if selectedBottleID == id {
            selectedBottleID = bottles.first?.id
        }
    }

    private func insertBottleSorted(_ summary: BottleSummary) {
        bottles.append(summary)
        bottles.sort { $0.settings.info.name.lowercased() < $1.settings.info.name.lowercased() }
    }

    public func addExistingBottle(at directoryURL: URL) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let summary = try await container.bottleRepository.addExistingBottle(at: directoryURL)
            await refreshBottles()
            selectedBottleID = summary.id
            await container.installLedger.record(
                path: summary.directoryURL,
                kind: .bottle,
                note: "Imported bottle \(summary.settings.info.name)"
            )
            toastMessage = "Imported \(summary.settings.info.name)."
        } catch {
            toastMessage = "Failed to open bottle: \(error.localizedDescription)"
        }
    }

    public func renameBottle(_ bottle: BottleSummary, to newName: String) async {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            var settings = bottle.settings
            settings.info.name = trimmedName
            try await container.bottleRepository.saveSettings(settings, for: bottle.id)
            await refreshBottles()
            selectedBottleID = bottle.id
            toastMessage = "Renamed bottle to \(trimmedName)."
        } catch {
            toastMessage = "Failed to rename bottle: \(error.localizedDescription)"
        }
    }

    public func moveBottle(_ bottle: BottleSummary, to destinationParent: URL) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let moved = try await container.bottleRepository.moveBottle(id: bottle.id, destinationParent: destinationParent)
            await refreshBottles()
            selectedBottleID = moved.id
            await container.installLedger.record(
                path: moved.directoryURL,
                kind: .bottle,
                note: "Moved bottle \(moved.settings.info.name)"
            )
            toastMessage = "Moved \(moved.settings.info.name)."
        } catch {
            toastMessage = "Failed to move bottle: \(error.localizedDescription)"
        }
    }

    public func exportBottle(_ bottle: BottleSummary, to destinationArchiveURL: URL) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await container.bottleRepository.exportBottle(id: bottle.id, destinationArchiveURL: destinationArchiveURL)
            toastMessage = "Exported \(bottle.settings.info.name)."
        } catch {
            toastMessage = "Failed to export bottle: \(error.localizedDescription)"
        }
    }

    public func deleteBottle(_ bottle: BottleSummary, removeFiles: Bool) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await container.bottleRepository.deleteBottle(id: bottle.id, removeFiles: removeFiles)
            await refreshBottles()
            toastMessage = "Removed \(bottle.settings.info.name)."
        } catch {
            toastMessage = "Failed to remove bottle: \(error.localizedDescription)"
        }
    }

    public func saveSettings(_ settings: AppSettings) async {
        appSettings = settings
        await container.settingsStore.saveSettings(settings)
        let bottleRoot = URL(fileURLWithPath: settings.defaultBottleDirectoryPath)
        await container.installLedger.record(
            path: bottleRoot,
            kind: .bottle,
            note: "Default bottle location"
        )
    }

    public func installRuntimeDependencies() async {
        setupStage = .checking

        do {
            if !(await container.rosettaService.isInstalled()) {
                setupStage = .installingRosetta
                let success = try await container.rosettaService.installIfNeeded()
                if !success {
                    setupStage = .failed("Rosetta installation did not complete successfully.")
                    return
                }
            }

            setupStage = .checkingGStreamer
            if !(await container.gstreamerService.isInstalled()) {
                toastMessage = "GStreamer.framework is not installed. Wine 11.16 uses it for media; games using DXVK/DXMT/D3DMetal still run. Install the official GStreamer runtime if videos fail."
            }

            setupStage = .fetchingRuntime
            let releases = try await container.runtimeInstaller.fetchLatestReleases()
            setupStage = .downloadingRuntime(0)
            let archives = try await container.runtimeInstaller.downloadAll(releases: releases) { [weak self] fraction in
                Task { @MainActor in
                    self?.setupStage = .downloadingRuntime(fraction)
                }
            }

            setupStage = .installingRuntime
            let (manifest, _) = try await container.runtimeInstaller.installAll(from: archives)
            runtimeManifest = manifest
            runtimeUpdateVersion = nil
            overlayDrifts = await container.runtimeInstaller.overlayDrifts()
            showSetupSheet = false
            setupStage = .ready
            await container.installLedger.seedKnownRoots()
            toastMessage = "Runtime installation complete."
        } catch {
            setupStage = .failed(error.localizedDescription)
        }
    }

    public func selectedBottle() -> BottleSummary? {
        guard let id = selectedBottleID else { return nil }
        return bottles.first(where: { $0.id == id })
    }

    public func killAllBottles() async {
        for bottle in bottles {
            await container.runtimeService.killBottle(bottle)
        }
        toastMessage = "Sent kill signal to all bottles."
    }

    public func openLogsFolder() {
        try? FileManager.default.createDirectory(at: container.paths.logsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: container.paths.logsDirectory.path(percentEncoded: false))
    }

    public func clearShaderCaches() async {
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/getconf"),
            arguments: ["DARWIN_USER_CACHE_DIR"],
            displayName: "getconf",
            timeout: 5
        )
        let cacheRoot: String
        do {
            let output = try await container.processRunner.captureProcess(spec, outputFileHandle: nil)
            cacheRoot = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cacheRoot.isEmpty else {
                toastMessage = "Unable to resolve cache directory."
                return
            }
        } catch {
            toastMessage = "Unable to inspect cache directory."
            return
        }

        let cacheURL = URL(fileURLWithPath: cacheRoot)
        let cachePaths = [
            cacheURL.appending(path: "d3dm"),
            cacheURL.appending(path: "dxmt")
        ]
        do {
            try await Task.detached(priority: .utility) {
                for path in cachePaths where FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: path)
                }
            }.value
            toastMessage = "Shader cache cleared."
        } catch {
            toastMessage = "Failed to clear shader cache: \(error.localizedDescription)"
        }
    }
}
