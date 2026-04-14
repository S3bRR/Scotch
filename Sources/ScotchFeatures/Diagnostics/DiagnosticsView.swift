import SwiftUI
import ScotchDomain

public struct DiagnosticsView: View {
    @ObservedObject private var appViewModel: AppViewModel
    @StateObject private var viewModel: DiagnosticsViewModel
    @Environment(\.dismiss) private var dismiss

    public init(appViewModel: AppViewModel) {
        self._appViewModel = ObservedObject(initialValue: appViewModel)
        _viewModel = StateObject(wrappedValue: DiagnosticsViewModel(container: appViewModel.container))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    if appViewModel.bottles.isEmpty {
                        Text("No bottles to inspect.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Bottle", selection: $viewModel.selectedBottleID) {
                            ForEach(appViewModel.bottles, id: \.id) { bottle in
                                Text(bottle.settings.info.name).tag(Optional(bottle.id))
                            }
                        }
                    }
                }

                Section("Processes") {
                    if viewModel.processes.isEmpty {
                        Text("No processes detected for this bottle.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.processes, id: \.id) { process in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(process.processName)
                                    Text("PID \(process.pid)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Kill") {
                                    Task { await viewModel.killProcess(pid: process.pid, bottles: appViewModel.bottles) }
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Environment") {
                    monospaceBlock(viewModel.environmentPreview.isEmpty ? "No environment data." : viewModel.environmentPreview)
                }

                Section("Logs") {
                    if viewModel.logURLs.isEmpty {
                        Text("No logs yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Log file", selection: $viewModel.selectedLogURL) {
                            ForEach(viewModel.logURLs, id: \.self) { logURL in
                                Text(logURL.lastPathComponent).tag(Optional(logURL))
                            }
                        }
                        monospaceBlock(viewModel.selectedLogText.isEmpty ? "Select a log to view." : viewModel.selectedLogText, maxHeight: 220)
                    }
                }

                Section("Migration Report") {
                    monospaceBlock(viewModel.migrationReportText)
                }

                Section("Effective Config") {
                    monospaceBlock(viewModel.effectiveConfigPreview, maxHeight: 220)
                }

                Section("Catalog Integrity") {
                    monospaceBlock(viewModel.orphanedEntriesText)
                }

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        InlineStatusView(text: statusMessage)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.refresh(bottles: appViewModel.bottles) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                }
            }
        }
        .frame(width: 720, height: 600)
        .task {
            await viewModel.refresh(bottles: appViewModel.bottles)
        }
        .onChange(of: viewModel.selectedBottleID) { _, _ in
            Task { await viewModel.refresh(bottles: appViewModel.bottles) }
        }
        .onChange(of: appViewModel.bottles) { _, _ in
            Task { await viewModel.refresh(bottles: appViewModel.bottles) }
        }
        .onChange(of: viewModel.selectedLogURL) { _, _ in
            Task { await viewModel.loadSelectedLogText() }
        }
    }

    @ViewBuilder
    private func monospaceBlock(_ text: String, maxHeight: CGFloat = 160) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.vertical, 4)
        }
        .frame(maxHeight: maxHeight)
    }
}
