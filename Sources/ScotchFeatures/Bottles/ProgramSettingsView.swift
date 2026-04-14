import SwiftUI
import ScotchDomain

private struct EnvironmentEntry: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
}

struct ProgramSettingsView: View {
    let program: ProgramRecord
    let onSave: (ProgramSettings) -> Void
    let onRun: (ProgramSettings) -> Void

    @State private var settings: ProgramSettings
    @State private var environmentEntries: [EnvironmentEntry]

    init(
        program: ProgramRecord,
        onSave: @escaping (ProgramSettings) -> Void,
        onRun: @escaping (ProgramSettings) -> Void
    ) {
        self.program = program
        self.onSave = onSave
        self.onRun = onRun

        let initialSettings = program.settings
        _settings = State(initialValue: initialSettings)
        _environmentEntries = State(initialValue: initialSettings.environment
            .map { EnvironmentEntry(key: $0.key, value: $0.value) }
            .sorted { $0.key.lowercased() < $1.key.lowercased() })
    }

    var body: some View {
        Form {
            Section("Program") {
                HStack {
                    Text("Executable")
                    Spacer()
                    Text(program.executableURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                }

                Picker("Locale", selection: $settings.locale) {
                    ForEach(ProgramLocale.allCases, id: \.self) { locale in
                        Text(locale.displayName).tag(locale)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Arguments")
                    TextField("Launch arguments", text: $settings.arguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section {
                ForEach($environmentEntries) { $entry in
                    HStack {
                        TextField("KEY", text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        TextField("VALUE", text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            environmentEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Variable", systemImage: "plus") {
                    environmentEntries.append(EnvironmentEntry(key: "", value: ""))
                }
            } header: {
                Text("Environment")
            } footer: {
                Text("Program env vars apply before temporary runtime overrides.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(program.displayName)
        .bottomBar {
            HStack {
                Spacer()
                Button("Save") {
                    syncEnvironmentEntries()
                    onSave(settings)
                }
                .buttonStyle(.glass)

                Button("Save & Run") {
                    syncEnvironmentEntries()
                    onSave(settings)
                    onRun(settings)
                }
                .buttonStyle(.glass)
                .tint(ScotchTheme.accent)
            }
            .padding()
        }
    }

    private func syncEnvironmentEntries() {
        var dictionary: [String: String] = [:]
        for entry in environmentEntries {
            let trimmedKey = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                continue
            }
            dictionary[trimmedKey] = entry.value
        }
        settings.environment = dictionary
    }
}

