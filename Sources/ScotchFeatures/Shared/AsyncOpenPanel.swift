import AppKit
import UniformTypeIdentifiers

/// Async wrapper around `NSOpenPanel.begin(_:)`. SwiftUI's `.fileImporter` doesn't expose
/// `directoryURL`, so we drop to AppKit when we need to pin the picker to a specific starting
/// location (e.g. a bottle's simulated `drive_c`). Using `begin` keeps us off the blocking
/// modal path while preserving the native picker UX, matching `AsyncSavePanel`.
@MainActor
enum AsyncOpenPanel {
    static func present(
        title: String? = nil,
        directoryURL: URL? = nil,
        allowedContentTypes: [UTType] = [],
        canChooseDirectories: Bool = false,
        canChooseFiles: Bool = true,
        allowsMultipleSelection: Bool = false
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            if let title { panel.title = title }
            if let directoryURL { panel.directoryURL = directoryURL }
            panel.canChooseDirectories = canChooseDirectories
            panel.canChooseFiles = canChooseFiles
            panel.allowsMultipleSelection = allowsMultipleSelection
            if !allowedContentTypes.isEmpty {
                panel.allowedContentTypes = allowedContentTypes
            }
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
