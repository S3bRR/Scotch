import Foundation
import ScotchDomain

@MainActor
public final class DiagnosticsViewModel: ObservableObject {
    @Published public var selectedBottleID: BottleID?
    @Published public var processes: [BottleProcessInfo] = []
    @Published public var environmentPreview: String = ""
    @Published public var logURLs: [URL] = []
    @Published public var selectedLogURL: URL?
    @Published public var selectedLogText: String = ""
    @Published public var migrationReportText: String = ""
    @Published public var orphanedEntriesText: String = ""
    @Published public var effectiveConfigPreview: String = ""
    @Published public var statusMessage: String?

    private let container: ScotchContainer

    public init(container: ScotchContainer) {
        self.container = container
    }

    public func refresh(bottles: [BottleSummary]) async {
        await refreshLogs()
        await refreshMigrationReport()
        await refreshOrphanedEntries()

        guard let bottle = currentBottle(from: bottles) else {
            processes = []
            environmentPreview = ""
            effectiveConfigPreview = ""
            return
        }

        await refreshEnvironment(for: bottle)
        await refreshEffectiveConfig(for: bottle)
        await refreshProcesses(for: bottle)
    }

    public func refreshLogs() async {
        logURLs = await container.runtimeService.recentLogs(limit: 200)
        if selectedLogURL == nil {
            selectedLogURL = logURLs.first
        }
        await loadSelectedLogText()
    }

    public func refreshMigrationReport() async {
        let report = await container.bottleRepository.migrationReport()
        migrationReportText = report.isEmpty
            ? "No migration fallback events were recorded."
            : report.map { "- \($0)" }.joined(separator: "\n")
    }

    public func refreshOrphanedEntries() async {
        let entries = await container.bottleRepository.orphanedCatalogEntries()
        orphanedEntriesText = entries.isEmpty
            ? "No orphaned catalog entries were detected."
            : entries.map { "- \($0)" }.joined(separator: "\n")
    }

    public func loadSelectedLogText() async {
        guard let selectedLogURL else {
            selectedLogText = ""
            return
        }
        selectedLogText = await container.runtimeService.readLog(at: selectedLogURL, maxCharacters: 50000)
    }

    public func refreshEnvironment(for bottle: BottleSummary) async {
        let environment = await container.runtimeService.makeShellEnvironment(for: bottle)
        environmentPreview = environment
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }

    public func refreshEffectiveConfig(for bottle: BottleSummary) async {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        if let data = try? encoder.encode(bottle.settings),
           let xml = String(data: data, encoding: .utf8) {
            effectiveConfigPreview = xml
        } else {
            effectiveConfigPreview = "Unable to encode bottle settings."
        }
    }

    public func refreshProcesses(for bottle: BottleSummary) async {
        do {
            processes = try await container.runtimeService.listProcesses(in: bottle)
        } catch {
            processes = []
            statusMessage = "Failed to load process list: \(error.localizedDescription)"
        }
    }

    public func killProcess(pid: Int, bottles: [BottleSummary]) async {
        guard let bottle = currentBottle(from: bottles) else { return }
        do {
            try await container.runtimeService.killProcess(pid: pid, in: bottle)
            await refreshProcesses(for: bottle)
            statusMessage = "Killed process \(pid)."
        } catch {
            statusMessage = "Failed to kill process \(pid): \(error.localizedDescription)"
        }
    }

    private func currentBottle(from bottles: [BottleSummary]) -> BottleSummary? {
        if selectedBottleID == nil {
            selectedBottleID = bottles.first?.id
        }
        guard let selectedBottleID else { return nil }
        return bottles.first(where: { $0.id == selectedBottleID })
    }
}
