import SwiftUI
import ScotchDomain

struct ConfigView: View {
    @Binding var settings: BottleSettings
    let zinkAvailable: Bool
    let onSave: () -> Void

    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("backendSectionExpanded") private var backendSectionExpanded: Bool = true
    @AppStorage("gpuSectionExpanded") private var gpuSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true

    var body: some View {
        Form {
            Section("Wine", isExpanded: $wineSectionExpanded) {
                Picker("Windows Version", selection: $settings.wine.windowsVersion) {
                    ForEach(WindowsVersion.allCases.reversed(), id: \.self) { version in
                        Text(version.displayName).tag(version)
                    }
                }

                Picker("Enhanced Sync", selection: $settings.wine.enhancedSync) {
                    Text("None").tag(EnhancedSyncMode.none)
                    Text("ESync").tag(EnhancedSyncMode.esync)
                    Text("MSync").tag(EnhancedSyncMode.msync)
                }

                Toggle(isOn: $settings.wine.avxEnabled) {
                    VStack(alignment: .leading) {
                        Text("Advertise AVX")
                        if settings.wine.avxEnabled {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .font(.subheadline)
                                Text("May cause instability in some applications.")
                                    .fontWeight(.light)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            Section("Backend", isExpanded: $backendSectionExpanded) {
                if zinkAvailable {
                    Toggle(isOn: $settings.backend.glZinkEnabled) {
                        Text("Enable Zink OpenGL")
                        Text("Translates OpenGL calls through Vulkan via the Zink driver.")
                    }
                    .disabled(settings.backend.backend == .zink)

                    Toggle(isOn: $settings.backend.steamBuiltinOpenGL) {
                        Text("Steam Builtin OpenGL Override")
                        Text("Uses Zink for Steam's built-in OpenGL renderer.")
                    }
                    .disabled(!(settings.backend.backend == .zink || settings.backend.glZinkEnabled))
                } else {
                    Text("Zink overlay is not installed.")
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $settings.backend.dxvkAsync) {
                    Text("DXVK Async")
                }
                .disabled(settings.backend.backend != .dxvk)

                Picker("DXVK HUD", selection: $settings.backend.dxvkHud) {
                    Text("Full").tag(DXVKHUD.full)
                    Text("Partial").tag(DXVKHUD.partial)
                    Text("FPS Only").tag(DXVKHUD.fps)
                    Text("Off").tag(DXVKHUD.off)
                }
                .disabled(settings.backend.backend != .dxvk)
            }

            Section("GPU", isExpanded: $gpuSectionExpanded) {
                Picker("GPU Spoof Preset", selection: $settings.gpu.spoofPreset) {
                    ForEach(GPUSpoofPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if settings.gpu.spoofPreset != .off {
                    Text("Games will see this GPU instead of the real hardware.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.gpu.spoofPreset == .custom {
                    HStack {
                        Text("Vendor ID")
                        Spacer()
                        TextField("Vendor ID", text: gpuHexBinding(for: \.customVendorId))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Device ID")
                        Spacer()
                        TextField("Device ID", text: gpuHexBinding(for: \.customDeviceId))
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Description")
                        Spacer()
                        TextField("Description", text: $settings.gpu.customDescription)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .labelsHidden()
                    }
                    HStack {
                        Text("VRAM")
                        Spacer()
                        TextField("VRAM", value: $settings.gpu.customVRAM, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                            .labelsHidden()
                        Text("MB")
                    }
                }
            }

            Section("Metal", isExpanded: $metalSectionExpanded) {
                Toggle(isOn: $settings.metal.metalHud) {
                    Text("Metal HUD")
                }

                Toggle(isOn: $settings.metal.metalTrace) {
                    Text("Metal Trace")
                    Text("Enables GPU capture for Metal debugging.")
                }

                Toggle(isOn: $settings.metal.dxrEnabled) {
                    Text("DirectX Raytracing")
                    Text("Requires Apple M3/A17 or later.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(.scotchDefault, value: wineSectionExpanded)
        .animation(.scotchDefault, value: backendSectionExpanded)
        .animation(.scotchDefault, value: gpuSectionExpanded)
        .animation(.scotchDefault, value: metalSectionExpanded)
        .animation(.scotchDefault, value: settings.gpu.spoofPreset)
        .bottomBar {
            HStack {
                Spacer()
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.glass)
                .tint(ScotchTheme.accent)
            }
            .padding()
        }
        .navigationTitle("Configuration")
    }

    private func gpuHexBinding(for keyPath: WritableKeyPath<BottleGPUConfig, UInt16>) -> Binding<String> {
        Binding<String>(
            get: { String(settings.gpu[keyPath: keyPath], radix: 16) },
            set: { newValue in
                if let parsed = UInt16(newValue, radix: 16) {
                    settings.gpu[keyPath: keyPath] = parsed
                }
            }
        )
    }
}
