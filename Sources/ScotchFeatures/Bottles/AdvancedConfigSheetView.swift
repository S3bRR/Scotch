import SwiftUI

struct AdvancedConfigSheetView: View {
    @ObservedObject var viewModel: BottleDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var buildVersion = 0
    @State private var retinaMode = false
    @State private var dpi = 96
    @State private var mouseFixEnabled = false
    @State private var loadedMouseFixEnabled = false
    @State private var isLoading = false
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Windows Settings") {
                    HStack {
                        Text("Build Version")
                        Spacer()
                        TextField("Build", value: $buildVersion, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("Retina Mode", isOn: $retinaMode)

                    HStack {
                        Text("DPI")
                        Slider(value: Binding(
                            get: { Double(dpi) },
                            set: { dpi = Int($0.rounded()) }
                        ), in: 96...480, step: 24)
                        Text("\(dpi)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Section("Mouse Settings") {
                    Toggle("Mouse Fix", isOn: $mouseFixEnabled)
                    Text("Forces Wine cursor warp and precise-scroll handling. Windows mouse acceleration is always disabled (stays off even when this toggle is off).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("If movement still feels off, the cause is usually macOS pointer acceleration or DXVK VSync — Wine can't override either. Try `defaults write NSGlobalDomain com.apple.mouse.scaling -1` (then re-login), turn DXVK VSync off, or run the game in exclusive fullscreen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("Tools") {
                    HStack {
                        Button("Control Panel") {
                            Task { await viewModel.runControlPanel() }
                        }
                        .buttonStyle(.glass)

                        Button("Regedit") {
                            Task { await viewModel.runRegedit() }
                        }
                        .buttonStyle(.glass)

                        Button("Winecfg") {
                            Task { await viewModel.runWineCfg() }
                        }
                        .buttonStyle(.glass)
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
            .navigationTitle("Advanced Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        Task {
                            isApplying = true
                            await viewModel.setBuildVersion(buildVersion)
                            await viewModel.setRetinaMode(retinaMode)
                            await viewModel.setDPI(dpi)
                            if mouseFixEnabled != loadedMouseFixEnabled {
                                await viewModel.setMouseFix(mouseFixEnabled)
                                loadedMouseFixEnabled = mouseFixEnabled
                            }
                            isApplying = false
                        }
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .disabled(isLoading || isApplying)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 520, height: 420)
        .background(.ultraThinMaterial)
        .task {
            isLoading = true
            let snapshot = await viewModel.fetchAdvancedConfig()
            buildVersion = snapshot.buildVersion
            retinaMode = snapshot.retinaMode
            dpi = snapshot.dpi
            mouseFixEnabled = snapshot.mouseFixEnabled
            loadedMouseFixEnabled = snapshot.mouseFixEnabled
            isLoading = false
        }
    }
}

