import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScotchDomain

public extension Notification.Name {
    static let scotchOpenSetup = Notification.Name("scotchOpenSetup")
    static let scotchOpenSettings = Notification.Name("scotchOpenSettings")
    static let scotchOpenDiagnostics = Notification.Name("scotchOpenDiagnostics")
    static let scotchOpenLogs = Notification.Name("scotchOpenLogs")
    static let scotchKillBottles = Notification.Name("scotchKillBottles")
    static let scotchOpenExistingBottle = Notification.Name("scotchOpenExistingBottle")
    static let scotchClearShaderCaches = Notification.Name("scotchClearShaderCaches")
    static let scotchOpenFileInBottle = Notification.Name("scotchOpenFileInBottle")
    static let scotchCLIInstallResult = Notification.Name("scotchCLIInstallResult")
}

public struct RootView: View {
    @StateObject private var viewModel: AppViewModel

    @State private var showCreateBottle = false
    @State private var showSettings = false
    @State private var showDiagnostics = false
    @State private var pendingRunFileURL: URL?
    @State private var bottleFilter = ""
    @State private var deletingBottle: BottleSummary?
    @State private var renamingBottle: BottleSummary?
    @State private var renameText = ""
    @State private var didFinishBootstrap = false
    @State private var queuedExternalOpenURLs: [URL] = []

    public init(container: ScotchContainer) {
        _viewModel = StateObject(wrappedValue: AppViewModel(container: container))
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .disabled(viewModel.isBusy)
        .sheet(isPresented: $showCreateBottle) {
            BottleCreationSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsPanelView(
                container: viewModel.container,
                settings: viewModel.appSettings,
                runtimeManifest: viewModel.runtimeManifest,
                onSave: { settings in
                    await viewModel.saveSettings(settings)
                }
            )
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView(appViewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { pendingRunFileURL != nil && viewModel.bottles.count > 1 },
            set: { show in
                if !show { pendingRunFileURL = nil }
            }
        )) {
            if let pendingRunFileURL {
                RunFileSelectionSheet(fileURL: pendingRunFileURL, bottles: viewModel.bottles) { bottle in
                    await runExternalFile(pendingRunFileURL, in: bottle)
                }
            }
        }
        .sheet(isPresented: $viewModel.showSetupSheet) {
            SetupSheetView(viewModel: viewModel)
        }
        .task {
            await viewModel.bootstrap()
            didFinishBootstrap = true
            await processQueuedExternalOpens()
        }
        .onOpenURL { url in
            Task { await handleExternalOpen(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenFileInBottle)) { notification in
            guard let url = notification.object as? URL else { return }
            Task { await handleExternalOpen(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenSetup)) { _ in
            viewModel.showSetupSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenDiagnostics)) { _ in
            showDiagnostics = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenLogs)) { _ in
            viewModel.openLogsFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchKillBottles)) { _ in
            Task { await viewModel.killAllBottles() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchOpenExistingBottle)) { _ in
            Task { await presentOpenExistingBottle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchClearShaderCaches)) { _ in
            Task { await viewModel.clearShaderCaches() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scotchCLIInstallResult)) { notification in
            if let message = notification.object as? String {
                viewModel.toastMessage = message
                if message.localizedCaseInsensitiveContains("Installed") {
                    Task {
                        await viewModel.container.installLedger.record(
                            path: URL(fileURLWithPath: "/usr/local/bin/scotch"),
                            kind: .cli,
                            note: "CLI symlink"
                        )
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 24)
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(4))
                        if viewModel.toastMessage == toast {
                            viewModel.toastMessage = nil
                        }
                    }
            }
        }
        .alert(
            "Rename Bottle",
            isPresented: Binding(
                get: { renamingBottle != nil },
                set: { if !$0 { renamingBottle = nil } }
            )
        ) {
            TextField("Bottle name", text: $renameText)
            Button("Rename") {
                if let bottle = renamingBottle {
                    let newName = renameText
                    renamingBottle = nil
                    Task { await viewModel.renameBottle(bottle, to: newName) }
                }
            }
            Button("Cancel", role: .cancel) {
                renamingBottle = nil
            }
        } message: {
            Text("Enter a new bottle name.")
        }
        .confirmationDialog(
            deletingBottle.map { "Delete \($0.settings.info.name)?" } ?? "",
            isPresented: Binding(
                get: { deletingBottle != nil },
                set: { if !$0 { deletingBottle = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let bottle = deletingBottle {
                    deletingBottle = nil
                    Task { await viewModel.deleteBottle(bottle, removeFiles: true) }
                }
            }
            Button("Cancel", role: .cancel) {
                deletingBottle = nil
            }
        } message: {
            Text("This permanently deletes the bottle and all files in it. This cannot be undone.")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateBottle = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .help("Create bottle")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refreshBottles() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .help("Refresh")
            }
        }
        .accentColor(ScotchTheme.accent)
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedBottleID) {
            ForEach(filteredBottles, id: \.id) { bottle in
                sidebarRow(for: bottle)
                    .tag(Optional(bottle.id))
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $bottleFilter, placement: .sidebar, prompt: "Search")
        .animation(.scotchDefault, value: bottleFilter)
    }

    @ViewBuilder
    private func sidebarRow(for bottle: BottleSummary) -> some View {
        if bottle.inFlight {
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.settings.info.name)
                ProgressView(value: bottle.setupProgress, total: 1)
                    .tint(ScotchTheme.accent)
            }
            .opacity(0.5)
            .selectionDisabled(true)
        } else if let setupError = bottle.setupErrorMessage {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(bottle.settings.info.name)
                }
                Text("Setup failed: \(setupError)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .contextMenu {
                Button("Dismiss Failed Entry", systemImage: "xmark.circle") {
                    viewModel.dismissFailedBottle(bottle.id)
                }
            }
            .selectionDisabled(true)
        } else {
            Text(bottle.settings.info.name)
                .opacity(bottle.isAvailable ? 1 : 0.5)
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        renameBottlePrompt(bottle)
                    }
                    .disabled(!bottle.isAvailable)

                    Button("Move Bottle", systemImage: "shippingbox.and.arrow.backward") {
                        moveBottlePrompt(bottle)
                    }
                    .disabled(!bottle.isAvailable)

                    Button("Export Bottle", systemImage: "arrowshape.turn.up.right") {
                        exportBottlePrompt(bottle)
                    }
                    .disabled(!bottle.isAvailable)

                    Divider()

                    Button("Show in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([bottle.directoryURL])
                    }
                    .disabled(!bottle.isAvailable)

                    Button("View Log", systemImage: "doc.text.magnifyingglass") {
                        Task {
                            if let logURL = await viewModel.container.runtimeService.latestLogURL(for: bottle) {
                                NSWorkspace.shared.open(logURL)
                            }
                        }
                    }
                    .disabled(!bottle.isAvailable)

                    Divider()

                    Button("Delete Including Files", systemImage: "trash.fill", role: .destructive) {
                        confirmDeleteBottle(bottle)
                    }
                }
        }
    }


    @ViewBuilder
    private var detail: some View {
        if let bottle = viewModel.selectedBottle() {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.runtimeUpdateVersion != nil || !viewModel.overlayDrifts.isEmpty {
                    driftBanner
                }
                BottleDetailView(container: viewModel.container, bottle: bottle)
                    .id(bottle.id)
            }
        } else {
            VStack(spacing: ScotchTheme.Spacing.large) {
                VStack(spacing: ScotchTheme.Spacing.medium) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tertiary)
                        .symbolRenderingMode(.hierarchical)
                    Text("Create your first bottle to get started.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button {
                        showCreateBottle = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Create Bottle")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                }
                .padding(ScotchTheme.Spacing.large)
                .scotchGlassCard(cornerRadius: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(ScotchTheme.Spacing.large)
        }
    }

    private var driftBanner: some View {
        HStack(spacing: ScotchTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.overlayDrifts, id: \.component) { drift in
                    Text("\(drift.component.displayName): \(drift.installedVersion ?? "-") \u{2192} \(drift.expectedVersion)")
                        .font(.caption)
                }
                if let version = viewModel.runtimeUpdateVersion {
                    Text("Runtime components do not match supported Wine \(version.description) matrix")
                        .font(.caption)
                }
            }
            Spacer()
            Button("Update") {
                viewModel.showSetupSheet = true
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(ScotchTheme.accent)
        }
        .padding(ScotchTheme.Spacing.small)
        .glassEffect(Glass.regular.tint(.yellow.opacity(0.18)), in: RoundedRectangle(cornerRadius: ScotchTheme.Radius.medium, style: .continuous))
        .padding(.horizontal, ScotchTheme.Spacing.medium)
        .padding(.top, ScotchTheme.Spacing.small)
    }

    private var filteredBottles: [BottleSummary] {
        if bottleFilter.isEmpty {
            return viewModel.bottles
        }
        return viewModel.bottles.filter {
            $0.settings.info.name.localizedCaseInsensitiveContains(bottleFilter)
        }
    }

    private func handleExternalOpen(_ url: URL) async {
        let supported = Set(["exe", "msi", "bat"])
        guard supported.contains(url.pathExtension.lowercased()) else { return }

        guard didFinishBootstrap else {
            queuedExternalOpenURLs.append(url)
            return
        }

        guard !viewModel.bottles.isEmpty else {
            viewModel.toastMessage = "Create a bottle before opening \(url.lastPathComponent)."
            return
        }

        if viewModel.bottles.count == 1, let bottle = viewModel.bottles.first {
            await runExternalFile(url, in: bottle)
            return
        }

        if viewModel.bottles.count > 1 {
            pendingRunFileURL = url
        }
    }

    private func processQueuedExternalOpens() async {
        let queued = queuedExternalOpenURLs
        queuedExternalOpenURLs.removeAll()
        for url in queued {
            await handleExternalOpen(url)
        }
    }

    private func runExternalFile(_ fileURL: URL, in bottle: BottleSummary) async {
        do {
            if fileURL.pathExtension.lowercased() == "bat" {
                try await viewModel.container.runtimeService.runBatchFile(at: fileURL, bottle: bottle, extraEnvironment: [:])
            } else {
                try await viewModel.container.runtimeService.runProgram(at: fileURL, arguments: [], bottle: bottle, extraEnvironment: [:])
            }
            viewModel.toastMessage = "Started \(fileURL.lastPathComponent) in \(bottle.settings.info.name)."
        } catch {
            viewModel.toastMessage = "Failed to run file: \(error.localizedDescription)"
        }
    }

    private func renameBottlePrompt(_ bottle: BottleSummary) {
        renameText = bottle.settings.info.name
        renamingBottle = bottle
    }

    private func presentOpenExistingBottle() async {
        if let url = await AsyncOpenPanel.present(
            title: "Open Existing Bottle",
            allowedContentTypes: [.folder],
            canChooseDirectories: true,
            canChooseFiles: false
        ) {
            await viewModel.addExistingBottle(at: url)
        }
    }

    private func moveBottlePrompt(_ bottle: BottleSummary) {
        Task {
            if let url = await AsyncOpenPanel.present(
                title: "Move Bottle",
                allowedContentTypes: [.folder],
                canChooseDirectories: true,
                canChooseFiles: false
            ) {
                await viewModel.moveBottle(bottle, to: url)
            }
        }
    }

    private func exportBottlePrompt(_ bottle: BottleSummary) {
        Task {
            if let destination = await AsyncSavePanel.present(
                suggestedName: "\(bottle.settings.info.name).tar"
            ) {
                await viewModel.exportBottle(bottle, to: destination)
            }
        }
    }

    private func confirmDeleteBottle(_ bottle: BottleSummary) {
        deletingBottle = bottle
    }
}
