import SwiftUI
import AppKit
import ScotchDomain

enum BottleStage: Hashable {
    case config
    case programs
    case programSettings(ProgramRecord)
}

struct ProgramsView: View {
    let programs: [ProgramRecord]
    let blocklistPaths: [String]
    let onRun: (ProgramRecord) -> Void
    let onRunInTerminal: (ProgramRecord) -> Void
    let onShortcut: (ProgramRecord) -> Void
    let onBlocklist: (ProgramRecord) -> Void
    let onUnblocklistPath: (String) -> Void
    let onConfigure: (ProgramRecord) -> Void

    @State private var searchText = ""

    private var searchResults: [ProgramRecord] {
        guard !searchText.isEmpty else { return programs }
        return programs.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var pinnedPrograms: [ProgramRecord] {
        searchResults.filter(\.pinned)
    }

    private var otherPrograms: [ProgramRecord] {
        searchResults.filter { !$0.pinned }
    }

    private var filteredBlocklist: [String] {
        guard !searchText.isEmpty else { return blocklistPaths }
        return blocklistPaths.filter { path in
            path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Form {
            if !pinnedPrograms.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedPrograms) { program in
                        ProgramItemView(
                            program: program,
                            onRun: { onRun(program) },
                            onRunInTerminal: { onRunInTerminal(program) },
                            onShortcut: { onShortcut(program) },
                            onBlocklist: { onBlocklist(program) },
                            onConfigure: { onConfigure(program) }
                        )
                    }
                }
            }

            Section("All Programs") {
                if otherPrograms.isEmpty && pinnedPrograms.isEmpty {
                    Text("No programs discovered yet. Install software in this bottle or run a file.")
                        .foregroundStyle(.secondary)
                } else if otherPrograms.isEmpty {
                    Text("All discovered programs are pinned.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(otherPrograms) { program in
                        ProgramItemView(
                            program: program,
                            onRun: { onRun(program) },
                            onRunInTerminal: { onRunInTerminal(program) },
                            onShortcut: { onShortcut(program) },
                            onBlocklist: { onBlocklist(program) },
                            onConfigure: { onConfigure(program) }
                        )
                    }
                }
            }

            Section("Blocklist") {
                if filteredBlocklist.isEmpty {
                    Text("No blocked program paths.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredBlocklist, id: \.self) { blockedPath in
                        BlockedPathRow(
                            blockedPath: blockedPath,
                            onRemove: { onUnblocklistPath(blockedPath) }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText)
        .animation(.scotchDefault, value: searchText)
        .navigationTitle("Programs")
    }
}

private struct ProgramItemView: View {
    let program: ProgramRecord
    let onRun: () -> Void
    let onRunInTerminal: () -> Void
    let onShortcut: () -> Void
    let onBlocklist: () -> Void
    let onConfigure: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            if program.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(ScotchTheme.accent)
                    .font(.caption)
            }

            VStack(alignment: .leading) {
                Text(program.displayName)
                Text(program.executableURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if program.discoveredFromStartMenu {
                    Text("Start Menu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(ScotchTheme.accent.opacity(0.12))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button {
                    onConfigure()
                } label: {
                    Image(systemName: "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Program Settings")

                Button {
                    onShortcut()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Create Shortcut")

                Button {
                    onRun()
                } label: {
                    Image(systemName: "play")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Run")
            }
        }
        .padding(.vertical, 2)
        .onHover { hover in
            isHovered = hover
        }
        .contextMenu {
            Button("Run", systemImage: "play") {
                onRun()
            }
            Button("Run In Terminal", systemImage: "terminal") {
                onRunInTerminal()
            }
            Button("Create Shortcut", systemImage: "square.and.arrow.up") {
                onShortcut()
            }
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([program.executableURL])
            }
            Divider()
            Button("Blocklist Program", systemImage: "hand.raised") {
                onBlocklist()
            }
            Button("Program Settings", systemImage: "gearshape") {
                onConfigure()
            }
        }
    }
}

private struct BlockedPathRow: View {
    let blockedPath: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: blockedPath).lastPathComponent)
                Text(blockedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove from blocklist")
            }
        }
        .padding(.vertical, 2)
        .onHover { hover in
            isHovered = hover
        }
        .contextMenu {
            Button("Remove from Blocklist", systemImage: "xmark") {
                onRemove()
            }
        }
    }
}
