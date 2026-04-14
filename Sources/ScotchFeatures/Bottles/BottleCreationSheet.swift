import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ScotchDomain

public struct BottleCreationSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var bottleName = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var locationPath: String = ""
    @State private var showLocationPicker = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $bottleName)
                    Picker("Windows Version", selection: $windowsVersion) {
                        ForEach(WindowsVersion.allCases.reversed(), id: \.self) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Location")
                        Spacer()
                        Text(locationPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                        Button("Browse") {
                            showLocationPicker = true
                        }
                    }
                } footer: {
                    Text("Default location is configured in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Create Bottle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        submit()
                    }
                    .buttonStyle(.glass)
                    .tint(ScotchTheme.accent)
                    .disabled(bottleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .onSubmit { submit() }
        }
        .frame(width: 460, height: 320)
        .background(.ultraThinMaterial)
        .fileImporter(
            isPresented: $showLocationPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                locationPath = url.path(percentEncoded: false)
            }
        }
        .onAppear {
            if locationPath.isEmpty {
                locationPath = viewModel.appSettings.defaultBottleDirectoryPath
            }
        }
    }

    private func submit() {
        let trimmed = bottleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let overrideURL = URL(fileURLWithPath: locationPath)
        dismiss()
        Task {
            await viewModel.createBottle(name: trimmed, windowsVersion: windowsVersion, location: overrideURL)
        }
    }
}
