import SwiftUI
import AppKit

public struct PersistentWindowGlass: NSViewRepresentable {
    private let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material = .underWindowBackground) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PinnedVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.isEmphasized = true
        view.state = .active
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}

private final class PinnedVisualEffectView: NSVisualEffectView {
    override var state: NSVisualEffectView.State {
        get { .active }
        set { super.state = .active }
    }
}
