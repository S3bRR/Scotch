import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScotchDomain
import ScotchRuntime

public struct SettingsPanelView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var showLocationPicker = false
    @State private var showUninstallConfirmation = false
    @Environment(\.dismiss) private var dismiss
    private let onSave: @MainActor (AppSettings) async -> Void

    public init(
        container: ScotchContainer,
        settings: AppSettings,
        runtimeManifest: RuntimeManifest?,
        onSave: @escaping @MainActor (AppSettings) async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(container: container, settings: settings, runtimeManifest: runtimeManifest))
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Kill bottle processes on app exit", isOn: $viewModel.settings.killProcessesOnTerminate)
                    Toggle("Check for runtime updates", isOn: $viewModel.settings.checkRuntimeUpdates)

                    HStack {
                        Text("Default bottle location")
                        Spacer()
                        Text(viewModel.settings.defaultBottleDirectoryPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Browse") {
                            showLocationPicker = true
                        }
                    }
                }

                Section("Runtime Versions") {
                    if let manifest = viewModel.runtimeManifest {
                        versionRow(label: "Wine", value: manifest.wineVersion)
                        versionRow(label: "DXVK", value: manifest.dxvkVersion)
                        versionRow(label: "DXMT", value: manifest.dxmtVersion)
                        versionRow(label: "D3DMetal", value: manifest.d3dmetalVersion ?? "—")
                        versionRow(label: "winemac patch", value: manifest.winemacPatchVersion ?? "—")
                        versionRow(label: "Zink", value: manifest.zinkVersion ?? "—")
                    } else {
                        Text("Runtime is not installed yet.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Runtime Versions") {
                        Task { await viewModel.refreshManifest() }
                    }
                }

                Section {
                    Toggle("Delete bottles and Windows prefixes", isOn: $viewModel.includeBottlesInUninstall)
                    Toggle("Move Scotch.app to Trash after uninstall", isOn: $viewModel.includeAppBundleInUninstall)
                        .disabled(UninstallService.packagedAppBundleURL() == nil)

                    Text(viewModel.uninstallSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let plan = viewModel.uninstallPlan {
                        ForEach(plan.existingTargets.prefix(12)) { target in
                            HStack {
                                Text(URL(fileURLWithPath: target.path).lastPathComponent)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: target.byteCount, countStyle: .file))
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospacedDigit())
                            }
                            .font(.caption)
                        }
                        if plan.existingTargets.count > 12 {
                            Text("and \(plan.existingTargets.count - 12) more…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Uninstall Scotch…", role: .destructive) {
                        Task {
                            await viewModel.refreshUninstallPreview()
                            showUninstallConfirmation = true
                        }
                    }
                    .disabled(viewModel.isUninstalling)
                } header: {
                    Text("Uninstall")
                } footer: {
                    Text("Removes Wine, translation backends, settings, logs, caches, the `scotch` command, leftover folders, recorded shortcuts, and optionally every bottle. Extra paths are stored in InstallLedger.plist as Scotch creates them.")
                }

                if let status = viewModel.statusMessage {
                    Section {
                        InlineStatusView(text: status)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save(using: onSave)
                            dismiss()
                        }
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .task {
                await viewModel.refreshUninstallPreview()
            }
            .onChange(of: viewModel.includeBottlesInUninstall) { _, _ in
                Task { await viewModel.refreshUninstallPreview() }
            }
            .onChange(of: viewModel.includeAppBundleInUninstall) { _, _ in
                Task { await viewModel.refreshUninstallPreview() }
            }
            .confirmationDialog(
                "Uninstall Scotch?",
                isPresented: $showUninstallConfirmation,
                titleVisibility: .visible
            ) {
                Button("Uninstall", role: .destructive) {
                    Task {
                        let shouldQuit = await viewModel.uninstallScotch()
                        if shouldQuit {
                            NSApp.terminate(nil)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.uninstallSummary + " This permanently deletes Scotch data from this Mac.")
            }
        }
        .frame(width: 620, height: 640)
        .background(.ultraThinMaterial)
        .fileImporter(
            isPresented: $showLocationPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                viewModel.settings.defaultBottleDirectoryPath = url.path(percentEncoded: false)
            }
        }
    }

    private func versionRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}
