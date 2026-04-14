import AppKit
import Foundation
import QuickLookThumbnailing
import ScotchRuntime

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let thumbnailSize = CGSize(width: request.maximumSize.width, height: request.maximumSize.height)
        let iconScaleFactor: CGFloat = 0.9
        let iconFrame = CGRect(
            x: (request.maximumSize.width - request.maximumSize.width * iconScaleFactor) / 2.0,
            y: (request.maximumSize.height - request.maximumSize.height * iconScaleFactor) / 2.0,
            width: request.maximumSize.width * iconScaleFactor,
            height: request.maximumSize.height * iconScaleFactor
        )

        let icon = iconImage(for: request.fileURL)
        let reply = QLThumbnailReply(contextSize: thumbnailSize) {
            icon.draw(in: iconFrame)
            return true
        }
        handler(reply, nil)
    }

    private func iconImage(for url: URL) -> NSImage {
        if let pe = try? PEFile(url: url),
           let extracted = pe.bestIcon(),
           extracted.isValid {
            return extracted
        }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
