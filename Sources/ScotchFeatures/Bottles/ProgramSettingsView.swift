import SwiftUI
import ScotchDomain

private struct EnvironmentEntry: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
}

struct ProgramSettingsView: View {
    let program: ProgramRecord
    let onSave: (ProgramSettings) async -> Bool
    let onRun: (ProgramSettings) async -> Void
    let onRecommend: (ProgramSettings) async -> ProgramGraphicsRecommendation
    let onRememberWorking: (ProgramSettings) async throws -> ProgramSettings

    @State private var settings: ProgramSettings
    @State private var environmentEntries: [EnvironmentEntry]
    @State private var recommendation: ProgramGraphicsRecommendation?
    @State private var working = false
    @State private var message: String?

    init(
        program: ProgramRecord,
        onSave: @escaping (ProgramSettings) async -> Bool,
        onRun: @escaping (ProgramSettings) async -> Void,
        onRecommend: @escaping (ProgramSettings) async -> ProgramGraphicsRecommendation,
        onRememberWorking: @escaping (ProgramSettings) async throws -> ProgramSettings
    ) {
        self.program = program
        self.onSave = onSave
        self.onRun = onRun
        self.onRecommend = onRecommend
        self.onRememberWorking = onRememberWorking

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

            Section("Graphics") {
                Picker("Backend selection", selection: $settings.graphicsMode) {
                    ForEach(ProgramGraphicsMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if settings.graphicsMode == .manual {
                    Picker("Backend", selection: $settings.manualBackend) {
                        ForEach(TranslationBackend.allCases, id: \.self) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                }
                if let recommendation {
                    LabeledContent("Architecture", value: recommendation.analysis.architecture.rawValue)
                    LabeledContent("Detected graphics", value: recommendation.analysis.apis.isEmpty ? "Unknown" : recommendation.analysis.apis.map(\.rawValue).sorted().joined(separator: ", "))
                    if recommendation.usesAuto && !recommendation.automatic {
                        Text("Auto → \(recommendation.currentBackend.displayName) (Bottle Setting)").fontWeight(.medium)
                    }
                    if let backend = recommendation.backend {
                        Text(recommendation.usesAuto && recommendation.automatic ? "Auto → \(backend.displayName)" : "\(settings.graphicsMode == .manual ? "Selected" : "Suggested"): \(backend.displayName)")
                            .fontWeight(.medium)
                    }
                    Text(recommendation.reason).font(.caption).foregroundStyle(.secondary)
                    if let issue = recommendation.availabilityIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                } else { ProgressView("Inspecting executable and graphics dependencies…") }
                if let confirmed = settings.confirmedGraphics {
                    LabeledContent("Confirmed working", value: confirmed.backend.displayName)
                    Button("Forget Working Choice") {
                        settings.confirmedGraphics = nil
                        message = "Save to forget this confirmation. Your manual choice is preserved."
                    }
                }
                Button("Remember Most Recent Launch as Working") {
                    working = true
                    Task {
                        defer { working = false }
                        do {
                            syncEnvironmentEntries()
                            settings = try await onRememberWorking(settings)
                            recommendation = await onRecommend(settings)
                            message = "Remembered the last launch setup. Auto can reuse it for this application and runtime."
                        } catch { message = error.localizedDescription }
                    }
                }
                Text("Confirm only after checking the application's window and rendering. Launching alone does not prove it works. Backend changes require idle Wine processes and a full bottle backup, including installed games. Large bottles need free space.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption).textSelection(.enabled) }
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
        .disabled(working)
        .task(id: "\(settings.graphicsMode.rawValue):\(settings.manualBackend.rawValue):\(settings.confirmedGraphics?.hashValue ?? 0)") {
            recommendation = await onRecommend(settings)
        }
        .bottomBar {
            HStack {
                Spacer()
                Button("Save") {
                    save(run: false)
                }
                .buttonStyle(.glass)

                Button("Save & Run") {
                    save(run: true)
                }
                .buttonStyle(.glass)
                .tint(ScotchTheme.accent)
            }
            .padding()
        }
    }

    private func save(run: Bool) {
        guard !working else { return }
        syncEnvironmentEntries()
        working = true
        Task {
            defer { working = false }
            guard await onSave(settings) else { message = "Settings could not be saved. The application was not launched."; return }
            message = "Settings saved."
            if run { await onRun(settings) }
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

