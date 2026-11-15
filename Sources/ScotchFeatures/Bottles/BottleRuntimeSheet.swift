import SwiftUI
import ScotchDomain
import ScotchRuntime

struct BottleRuntimeSheet: View {
    let container: ScotchContainer
    @ObservedObject var viewModel: BottleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var sets: [ApprovedRuntimeSet] = []
    @State private var selected = ""
    @State private var message = ""
    @State private var working = false
    @State private var canRestore = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bottle Runtime").font(.title2.bold())
            Text("Keep a working game on its current runtime, or switch to an installed update. Switching creates a full backup of this bottle, including its saves and registry. Close games before continuing.")
                .foregroundStyle(.secondary)
            Picker("Runtime", selection: $selected) {
                Text("Original runtime").tag("")
                ForEach(sets) { Text($0.title).tag($0.id) }
            }
            if working { ProgressView("Backing up or restoring the bottle…") }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                if canRestore { Button("Restore Last Snapshot") { run(restore: true) } }
                Button("Back Up and Switch") { run(restore: false) }
                    .disabled(selected == (viewModel.bottle.settings.runtimeSetID ?? ""))
            }
        }
        .padding(24).frame(width: 600).disabled(working).interactiveDismissDisabled(working)
        .task {
            selected = viewModel.bottle.settings.runtimeSetID ?? ""
            sets = await container.runtimeUpdates.installedSets()
            canRestore = await BottleRuntimeManager(paths: container.paths).hasSnapshot(for: viewModel.bottle)
        }
    }
    private func run(restore: Bool) {
        working = true
        Task {
            defer { working = false }
            do {
                let manager = BottleRuntimeManager(paths: container.paths)
                let changed: BottleSummary
                if restore { changed = try await manager.restore(for: viewModel.bottle) }
                else { changed = try await manager.switchRuntime(for: viewModel.bottle, to: selected == "" ? nil : selected) }
                viewModel.adoptBottle(changed)
                NotificationCenter.default.post(name: .scotchBottleRuntimeChanged, object: nil)
                selected = changed.settings.runtimeSetID ?? ""
                canRestore = await manager.hasSnapshot(for: changed)
                message = restore ? "Snapshot restored. The replaced bottle was retained beside the snapshot for recovery." : "Runtime selected. A complete snapshot was saved before the change."
                await viewModel.refresh()
            } catch { message = error.localizedDescription }
        }
    }
}
