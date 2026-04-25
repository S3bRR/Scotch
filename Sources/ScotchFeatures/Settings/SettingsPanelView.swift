import SwiftUI
import UniformTypeIdentifiers
import ScotchDomain

public struct SettingsPanelView: View {
    @StateObject private var viewModel: SettingsViewModel
    @State private var showLocationPicker = false
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
        }
        .frame(width: 560, height: 480)
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
