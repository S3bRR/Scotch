import SwiftUI

public struct SetupSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ScotchTheme.Spacing.large) {
            VStack(alignment: .leading, spacing: ScotchTheme.Spacing.xSmall) {
                Text("Scotch Setup")
                    .font(.title2.weight(.semibold))
                Text("Rosetta, Wine Staging 11.16, and translation backends are required before creating or launching bottles.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            stageView
                .frame(minHeight: 60)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ScotchTheme.Spacing.medium)
                .scotchGlassCard(cornerRadius: 14)

            HStack {
                Button(canDismiss ? "Close" : "Quit") {
                    if canDismiss {
                        dismiss()
                    } else {
                        NSApp.terminate(nil)
                    }
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(installButtonTitle) {
                    Task { await viewModel.installRuntimeDependencies() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glass)
                .tint(ScotchTheme.accent)
                .disabled(installButtonDisabled)
            }
        }
        .padding(ScotchTheme.Spacing.large)
        .frame(width: 520)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var stageView: some View {
        switch viewModel.setupStage {
        case .idle:
            HStack(spacing: ScotchTheme.Spacing.small) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(ScotchTheme.accent)
                Text("Ready to install dependencies.")
            }
        case .checking:
            HStack(spacing: ScotchTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking installation status...")
            }
        case .installingRosetta:
            HStack(spacing: ScotchTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing Rosetta...")
            }
        case .checkingGStreamer:
            HStack(spacing: ScotchTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking GStreamer.framework...")
            }
        case .fetchingRuntime:
            HStack(spacing: ScotchTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Resolving latest runtime releases...")
            }
        case .downloadingRuntime(let fraction):
            VStack(alignment: .leading, spacing: ScotchTheme.Spacing.xSmall) {
                ProgressView(value: fraction, total: 1)
                    .tint(ScotchTheme.accent)
                Text("Downloading runtime: \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .installingRuntime:
            HStack(spacing: ScotchTheme.Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                Text("Installing Wine and translation backends...")
            }
        case .ready:
            HStack(spacing: ScotchTheme.Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(ScotchTheme.accent)
                Text("Setup complete.")
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: ScotchTheme.Spacing.small) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                Text("Setup failed: \(message)")
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }
        }
    }

    private var canDismiss: Bool {
        switch viewModel.setupStage {
        case .ready: return true
        default: return false
        }
    }

    private var installButtonTitle: String {
        switch viewModel.setupStage {
        case .ready: "Reinstall"
        case .failed: "Retry"
        default: "Install"
        }
    }

    private var installButtonDisabled: Bool {
        switch viewModel.setupStage {
        case .checking, .installingRosetta, .checkingGStreamer, .fetchingRuntime, .downloadingRuntime, .installingRuntime:
            return true
        default:
            return false
        }
    }
}
