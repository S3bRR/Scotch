import SwiftUI
import ScotchDomain

public struct RunFileSelectionSheet: View {
    public let fileURL: URL
    public let bottles: [BottleSummary]
    public let runAction: @Sendable (BottleSummary) async -> Void

    @State private var selectedID: BottleID?
    @Environment(\.dismiss) private var dismiss

    public init(fileURL: URL, bottles: [BottleSummary], runAction: @escaping @Sendable (BottleSummary) async -> Void) {
        self.fileURL = fileURL
        self.bottles = bottles
        self.runAction = runAction
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                        Text(fileURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Picker("Bottle", selection: $selectedID) {
                        ForEach(bottles, id: \.id) { bottle in
                            Text(bottle.settings.info.name).tag(Optional(bottle.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Run File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Run") {
                        guard let selectedID, let bottle = bottles.first(where: { $0.id == selectedID }) else { return }
                        Task {
                            await runAction(bottle)
                            dismiss()
                        }
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID == nil)
                }
            }
        }
        .frame(width: 460, height: 260)
        .background(.ultraThinMaterial)
        .onAppear {
            selectedID = bottles.first?.id
        }
    }
}
