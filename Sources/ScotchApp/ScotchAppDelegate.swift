import Foundation
import AppKit
import ScotchFeatures

@MainActor
final class ScotchAppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedContainer: ScotchContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pinAllWindowsGlass), name: NSWindow.didResignKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(pinAllWindowsGlass), name: NSWindow.didResignMainNotification, object: nil)
        center.addObserver(self, selector: #selector(pinAllWindowsGlass), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(pinAllWindowsGlass), name: NSApplication.didResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(pinAllWindowsGlass), name: NSApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(quitAfterUninstall), name: .scotchDidUninstall, object: nil)
    }

    private var didUninstall = false

    /// Scotch's files (and possibly the app itself) are gone, so quit for real:
    /// AppKit won't terminate while a sheet is attached, and the usual cleanup
    /// would recreate settings and catalog files that were just deleted.
    @objc private func quitAfterUninstall() {
        didUninstall = true
        for window in NSApp.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exit(0)
        }
    }

    @objc private func pinAllWindowsGlass() {
        for window in NSApp.windows where window.isVisible {
            guard let contentView = window.contentView else { continue }
            Self.forceActiveVisualEffectState(in: contentView)
        }
    }

    private static func forceActiveVisualEffectState(in view: NSView) {
        if let effect = view as? NSVisualEffectView {
            effect.state = .active
        }
        for subview in view.subviews {
            forceActiveVisualEffectState(in: subview)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didUninstall, let container = Self.sharedContainer else { return .terminateNow }

        let deadline = Date().addingTimeInterval(3.5)
        Task { @MainActor in
            await container.performTerminationCleanup(deadline: deadline)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let directObject = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        let descriptor = directObject.numberOfItems > 0 ? directObject.atIndex(1) : directObject
        guard let urlData = descriptor?.coerce(toDescriptorType: typeFileURL)?.data,
              let urlString = String(data: urlData, encoding: .utf8),
              let url = URL(string: urlString) else {
            return
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .scotchOpenFileInBottle, object: url)
        }
    }
}
