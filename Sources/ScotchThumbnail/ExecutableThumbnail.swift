import Foundation
import AppKit

public enum ExecutableThumbnail {
    /// Returns a best-effort icon image for a Windows executable path.
    /// A dedicated QuickLook extension can call this helper for rendering.
    public static func icon(forExecutableAt url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
