import AppKit
import UniformTypeIdentifiers

/// Async wrapper around `NSSavePanel.begin(_:)`. SwiftUI's `.fileExporter` requires a
/// `FileDocument`, which doesn't fit our flow where the actual save (tar export, shortcut
/// generation) is performed asynchronously by services using the URL the user picked. Using
/// `NSSavePanel.begin` instead of `.runModal()` keeps us off the SwiftUI-blocking modal path
/// while preserving the native save-panel UX.
@MainActor
enum AsyncSavePanel {
    static func present(
        title: String? = nil,
        suggestedName: String,
        allowedContentTypes: [UTType] = [],
        canCreateDirectories: Bool = true
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            if let title { panel.title = title }
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = canCreateDirectories
            if !allowedContentTypes.isEmpty {
                panel.allowedContentTypes = allowedContentTypes
            }
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
