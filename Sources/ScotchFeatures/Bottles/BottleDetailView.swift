import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScotchDomain
import ScotchRuntime

public struct BottleDetailView: View {
    private let container: ScotchContainer
    private let bottle: BottleSummary
    @StateObject private var viewModel: BottleDetailViewModel
    @State private var editableSettings: BottleSettings
    @State private var programLoading = false
    @State private var renamingProgram: ProgramRecord?
    @State private var renameText: String = ""
    @State private var showWinetricks = false
    @State private var showAdvancedConfig = false
    @State private var navigationPath = NavigationPath()

    private let gridLayout = [GridItem(.adaptive(minimum: 110, maximum: .infinity), spacing: 12)]

    public init(container: ScotchContainer, bottle: BottleSummary) {
        self.container = container
        self.bottle = bottle
        _viewModel = StateObject(wrappedValue: BottleDetailViewModel(container: container, bottle: bottle))
        _editableSettings = State(initialValue: bottle.settings)
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: ScotchTheme.Spacing.medium) {
                    pinnedGrid
                    backendCard
                    navCards
                }
                .padding(ScotchTheme.Spacing.medium)
            }
            .scrollContentBackground(.hidden)
            .bottomBar {
                HStack(spacing: ScotchTheme.Spacing.small) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            Button {
                                NotificationCenter.default.post(name: .scotchOpenSetup, object: nil)
                            } label: {
                                Image(systemName: "wrench.and.screwdriver")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .scotchGlassInteractive(cornerRadius: 8)
                            .help("Setup")

                            Button {
                                NotificationCenter.default.post(name: .scotchOpenSettings, object: nil)
                            } label: {
                                Image(systemName: "gearshape")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .scotchGlassInteractive(cornerRadius: 8)
                            .help("Settings")

                            Button {
                                NotificationCenter.default.post(name: .scotchOpenDiagnostics, object: nil)
                            } label: {
                                Image(systemName: "stethoscope")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .scotchGlassInteractive(cornerRadius: 8)
                            .help("Diagnostics")
                        }
                    }

                    Spacer()
                    if !viewModel.steamInstalled {
                        Button {
                            Task { await viewModel.installSteam() }
                        } label: {
                            if viewModel.isInstallingSteam {
                                Label("Installing…", systemImage: "gamecontroller")
                            } else {
                                Label("Install Steam", systemImage: "gamecontroller")
                            }
                        }
                        .disabled(viewModel.isInstallingSteam)
                    }
                    Button("C: Drive") {
                        viewModel.openCDrive()
                    }
                    Button("Terminal") {
                        Task { await viewModel.openBottleTerminal() }
                    }
                    Button("View Log") {
                        Task { await viewModel.openRecentLog() }
                    }
                    Button("Winetricks") {
                        showWinetricks = true
                    }
                    Button("Advanced") {
                        showAdvancedConfig = true
                    }
                    Button {
                        runFile()
                    } label: {
                        Label("Run File", systemImage: "play.fill")
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    if programLoading || viewModel.isLaunching || viewModel.isInstallingSteam {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 4)
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.bottle.settings.info.name)
            .navigationDestination(for: BottleStage.self) { stage in
                switch stage {
                case .config:
                    ConfigView(
                        settings: $editableSettings,
                        zinkAvailable: isBackendAvailable(.zink),
                        onSave: saveSettings
                    )
                case .programs:
                    ProgramsView(
                        programs: viewModel.programs,
                        blocklistPaths: viewModel.bottle.settings.info.blocklist,
                        onRun: { program in
                            Task { await viewModel.runProgram(program) }
                        },
                        onRunInTerminal: { program in
                            Task { await viewModel.runProgramInTerminal(program) }
                        },
                        onShortcut: shortcut,
                        onBlocklist: { program in
                            Task { await viewModel.addProgramToBlocklist(program) }
                        },
                        onUnblocklistPath: { blockedPath in
                            Task { await viewModel.removeBlockedPath(blockedPath) }
                        },
                        onConfigure: { program in
                            navigationPath.append(BottleStage.programSettings(program))
                        }
                    )
                case .programSettings(let program):
                    ProgramSettingsView(
                        program: program,
                        onSave: { updatedSettings in
                            Task { await viewModel.saveProgramSettings(updatedSettings, for: program) }
                        },
                        onRun: { updatedSettings in
                            var stagedProgram = program
                            stagedProgram.settings = updatedSettings
                            Task { await viewModel.runProgram(stagedProgram) }
                        }
                    )
                }
            }
        }
        .disabled(!viewModel.bottle.isAvailable)
        .task {
            await viewModel.refresh()
            editableSettings = viewModel.bottle.settings
        }
        .onChange(of: bottle) { _, newValue in
            viewModel.bottle = newValue
            editableSettings = newValue.settings
        }
        .sheet(item: $renamingProgram) { program in
            RenamePinSheet(
                originalName: program.displayName,
                text: $renameText,
                onSave: { newName in
                    Task { await viewModel.renamePin(program, to: newName) }
                }
            )
        }
        .sheet(isPresented: $showWinetricks) {
            WinetricksSheetView(container: container, bottle: viewModel.bottle)
        }
        .sheet(isPresented: $showAdvancedConfig) {
            AdvancedConfigSheetView(viewModel: viewModel)
        }
    }

    // MARK: - Pinned grid

    @ViewBuilder
    private var pinnedGrid: some View {
        let pinned = viewModel.programs.filter(\.pinned)
        VStack(alignment: .leading, spacing: ScotchTheme.Spacing.small) {
            HStack {
                Label("Pinned", systemImage: "pin.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !pinned.isEmpty {
                    Text("\(pinned.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)

            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: gridLayout, alignment: .center, spacing: 12) {
                    ForEach(pinned) { program in
                        PinTile(
                            program: program,
                            onRun: { Task { await viewModel.runProgram(program) } },
                            onRunInTerminal: { Task { await viewModel.runProgramInTerminal(program) } },
                            onUnpin: { Task { await viewModel.unpin(program) } },
                            onRename: {
                                renameText = program.displayName
                                renamingProgram = program
                            },
                            onShortcut: { shortcut(program) },
                            onConfigure: { navigationPath.append(BottleStage.programSettings(program)) }
                        )
                    }
                    PinAddTile(action: addPin)
                }
            }
        }
    }

    // MARK: - Backend (prominent)

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: ScotchTheme.Spacing.small) {
            HStack {
                Label("Backend", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: ScotchTheme.Spacing.small) {
                Image(systemName: backendIcon(for: editableSettings.backend.backend))
                    .font(.title2)
                    .foregroundStyle(ScotchTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(editableSettings.backend.backend.displayName)
                        .font(.body.weight(.medium))
                    Text(backendDescription(for: editableSettings.backend.backend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Picker("", selection: $editableSettings.backend.backend) {
                    ForEach(availableBackends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
                .onChange(of: editableSettings.backend.backend) { _, _ in
                    saveSettings()
                }
            }
            .padding(ScotchTheme.Spacing.medium)
            .scotchGlassCard(cornerRadius: 14)
        }
    }

    // MARK: - Navigation cards

    private var navCards: some View {
        HStack(spacing: ScotchTheme.Spacing.small) {
            NavigationLink(value: BottleStage.programs) {
                NavCardLabel(
                    title: "Programs",
                    subtitle: "\(viewModel.programs.count) discovered",
                    systemImage: "list.bullet"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: BottleStage.config) {
                NavCardLabel(
                    title: "Configuration",
                    subtitle: "Wine, GPU, Metal",
                    systemImage: "gearshape"
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func saveSettings() {
        Task {
            await viewModel.saveSettings(editableSettings)
            await viewModel.refresh()
        }
    }

    private func runFile() {
        Task {
            guard let url = await AsyncOpenPanel.present(
                directoryURL: bottleDriveCURL,
                allowedContentTypes: Self.runFileContentTypes
            ) else { return }
            programLoading = true
            await viewModel.runFileURL(url)
            programLoading = false
        }
    }

    private func addPin() {
        Task {
            guard let url = await AsyncOpenPanel.present(
                directoryURL: bottleDriveCURL,
                allowedContentTypes: Self.pinContentTypes
            ) else { return }
            await viewModel.pinExecutable(at: url)
        }
    }

    private var bottleDriveCURL: URL {
        bottle.directoryURL.appending(path: "drive_c")
    }

    private func shortcut(_ program: ProgramRecord) {
        Task {
            if let destination = await AsyncSavePanel.present(
                suggestedName: "\(program.displayName).app",
                allowedContentTypes: [.applicationBundle]
            ) {
                await viewModel.createShortcut(for: program, destination: destination)
            }
        }
    }

    private static let runFileContentTypes: [UTType] = [
        UTType(filenameExtension: "exe") ?? .data,
        UTType(filenameExtension: "msi") ?? .data,
        UTType(filenameExtension: "bat") ?? .data
    ]
    private static let pinContentTypes: [UTType] = [
        UTType(filenameExtension: "exe") ?? .data
    ]

    private func backendIcon(for backend: TranslationBackend) -> String {
        switch backend {
        case .dxvk: "diamond.fill"
        case .dxmt: "square.stack.3d.up.fill"
        case .d3dmetal: "m.square.fill"
        case .zink: "circle.hexagongrid.fill"
        case .none: "minus.circle"
        }
    }

    private func backendDescription(for backend: TranslationBackend) -> String {
        switch backend {
        case .dxvk: "DirectX 9/10/11 via Vulkan"
        case .dxmt: "DirectX 10/11 native Metal"
        case .d3dmetal: "Apple Game Porting Toolkit"
        case .zink: "OpenGL via Vulkan"
        case .none: "No translation"
        }
    }

    private var availableBackends: [TranslationBackend] {
        var backends = TranslationBackend.allCases.filter(isBackendAvailable)
        if !backends.contains(editableSettings.backend.backend) {
            backends.insert(editableSettings.backend.backend, at: 0)
        }
        return backends
    }

    private func isBackendAvailable(_ backend: TranslationBackend) -> Bool {
        switch backend {
        case .d3dmetal:
            let d3d12Path = container.paths.librariesDirectory
                .appending(path: "D3DMetal/x64/d3d12.dll")
                .path(percentEncoded: false)
            let frameworkPath = container.paths.librariesDirectory
                .appending(path: "D3DMetal/D3DMetal.framework/Versions/A/D3DMetal")
                .path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: d3d12Path) && FileManager.default.fileExists(atPath: frameworkPath)
        case .zink:
            return FileManager.default.fileExists(
                atPath: container.paths.librariesDirectory
                    .appending(path: "Zink/x64/opengl32.dll")
                    .path(percentEncoded: false)
            )
        default:
            return true
        }
    }

}

// MARK: - PinTile

private struct PinTile: View {
    let program: ProgramRecord
    let onRun: () -> Void
    let onRunInTerminal: () -> Void
    let onUnpin: () -> Void
    let onRename: () -> Void
    let onShortcut: () -> Void
    let onConfigure: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onRun) {
            VStack(spacing: 8) {
                ZStack {
                    AppIconView(url: program.executableURL)
                        .frame(width: 56, height: 56)
                    if isHovered {
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 56, height: 56)
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 64, height: 64)
                .glassEffect(
                    isHovered ? ScotchGlass.accentTinted.interactive() : ScotchGlass.interactive,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                Text(program.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 96)
                    .foregroundStyle(.primary)
            }
            .frame(width: 110, height: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.scotchDefault) { isHovered = hover }
        }
        .contextMenu {
            Button("Run", systemImage: "play") { onRun() }
            Button("Run In Terminal", systemImage: "terminal") { onRunInTerminal() }
            Button("Program Settings", systemImage: "gearshape") { onConfigure() }
            Button("Rename...", systemImage: "pencil") { onRename() }
            Button("Create Shortcut", systemImage: "square.and.arrow.up") { onShortcut() }
            Divider()
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([program.executableURL])
            }
            Divider()
            Button("Unpin", systemImage: "pin.slash", role: .destructive) { onUnpin() }
        }
    }
}

// MARK: - PinAddTile

private struct PinAddTile: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(isHovered ? ScotchTheme.accent : .secondary)
                }
                .frame(width: 64, height: 64)
                .glassEffect(
                    isHovered ? ScotchGlass.accentTinted.interactive() : ScotchGlass.interactive,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

                Text("Pin .exe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 96)
            }
            .frame(width: 110, height: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.scotchDefault) { isHovered = hover }
        }
        .help("Pin a Windows executable")
    }
}

// MARK: - AppIconView

private struct AppIconView: View {
    let url: URL
    private static let iconCache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let nsImage = loadIcon() {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private func loadIcon() -> NSImage? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        if let cached = Self.iconCache.object(forKey: path as NSString) {
            return cached
        }

        if let peFile = try? PEFile(url: url),
           let executableIcon = peFile.bestIcon(),
           executableIcon.isValid {
            executableIcon.size = NSSize(width: 56, height: 56)
            Self.iconCache.setObject(executableIcon, forKey: path as NSString)
            return executableIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 56, height: 56)
        Self.iconCache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

// MARK: - NavCardLabel

private struct NavCardLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: ScotchTheme.Spacing.small) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ScotchTheme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(ScotchTheme.Spacing.medium)
        .frame(maxWidth: .infinity)
        .scotchGlassInteractive(cornerRadius: 14)
        .onHover { hover in
            withAnimation(.scotchDefault) { isHovered = hover }
        }
    }
}

// MARK: - Rename sheet

private struct RenamePinSheet: View {
    let originalName: String
    @Binding var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $text)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Rename Pin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 380, height: 180)
        .background(.ultraThinMaterial)
    }
}
