import SwiftUI
import ScotchDomain

@MainActor
final class WinetricksSheetViewModel: ObservableObject {
    @Published var categories: [WinetricksCategoryListing] = []
    @Published var selectedCategory: WinetricksCategory?
    @Published var selectedVerbName: String?
    @Published var command: String = ""
    @Published var executionMode: WinetricksExecutionMode = .terminal
    @Published var isLoading = false
    @Published var isRunning = false
    @Published var statusMessage: String?

    private let container: ScotchContainer
    private let bottle: BottleSummary

    init(container: ScotchContainer, bottle: BottleSummary) {
        self.container = container
        self.bottle = bottle
    }

    var verbsInSelectedCategory: [WinetricksVerb] {
        guard let selectedCategory else { return [] }
        return categories.first(where: { $0.category == selectedCategory })?.verbs ?? []
    }

    func loadVerbs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            categories = try await container.winetricksService.parseVerbs()
            if selectedCategory == nil {
                selectedCategory = categories.first?.category
            }
            statusMessage = nil
        } catch {
            statusMessage = "Failed to load verbs: \(error.localizedDescription)"
        }
    }

    func selectVerb(_ verb: WinetricksVerb) {
        selectedVerbName = verb.name
        command = verb.name
    }

    func runSelectedCommand() async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Select a verb or enter a command."
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let output = try await container.winetricksService.run(command: trimmed, in: bottle, mode: executionMode)
            if executionMode == .headless {
                let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = cleaned.isEmpty ? "Command completed." : cleaned
            } else {
                statusMessage = "Command launched in Terminal."
            }
        } catch {
            statusMessage = "Winetricks failed: \(error.localizedDescription)"
        }
    }
}

struct WinetricksSheetView: View {
    @StateObject private var viewModel: WinetricksSheetViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: ScotchContainer, bottle: BottleSummary) {
        _viewModel = StateObject(wrappedValue: WinetricksSheetViewModel(container: container, bottle: bottle))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ScotchTheme.Spacing.medium) {
                HStack {
                    Picker("Mode", selection: $viewModel.executionMode) {
                        Text("Terminal").tag(WinetricksExecutionMode.terminal)
                        Text("Headless").tag(WinetricksExecutionMode.headless)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    Spacer()

                    Button("Reload") {
                        Task { await viewModel.loadVerbs() }
                    }
                    .buttonStyle(.glass)
                }

                if viewModel.isLoading {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    Spacer()
                } else {
                    HStack(alignment: .top, spacing: ScotchTheme.Spacing.medium) {
                        List(selection: $viewModel.selectedCategory) {
                            ForEach(viewModel.categories, id: \.category) { section in
                                Text(section.category.rawValue.capitalized)
                                    .tag(Optional(section.category))
                            }
                        }
                        .frame(minWidth: 180, maxWidth: 220, minHeight: 320)

                        List(viewModel.verbsInSelectedCategory, id: \.id) { verb in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verb.name)
                                    .font(.body.monospaced())
                                Text(verb.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectVerb(verb)
                            }
                            .background(
                                viewModel.selectedVerbName == verb.name
                                ? RoundedRectangle(cornerRadius: 8).fill(ScotchTheme.accent.opacity(0.12))
                                : nil
                            )
                        }
                        .frame(minWidth: 420, minHeight: 320)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Command")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Verb or command", text: $viewModel.command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                if let statusMessage = viewModel.statusMessage {
                    InlineStatusView(text: statusMessage)
                }
            }
            .padding(ScotchTheme.Spacing.large)
            .navigationTitle("Winetricks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(viewModel.isRunning ? "Running..." : "Run") {
                        Task { await viewModel.runSelectedCommand() }
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .disabled(viewModel.isRunning)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .task {
                await viewModel.loadVerbs()
            }
        }
        .frame(width: 900, height: 620)
        .background(.ultraThinMaterial)
    }
}

