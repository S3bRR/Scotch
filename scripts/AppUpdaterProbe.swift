import AppKit
import Foundation
import ScotchFeatures
import ScotchInfrastructure

/// Real Sparkle + the shipping one-action coordinator, isolated from user data.
@main
struct AppUpdaterProbe {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let environment = ProcessInfo.processInfo.environment
        let markerPath = environment["SCOTCH_PROBE_MARKER"] ?? Bundle.main.object(forInfoDictionaryKey: "ScotchProbeMarker") as! String
        let marker = URL(fileURLWithPath: markerPath)
        let runtimeFeed = environment["SCOTCH_PROBE_RUNTIME_FEED"] ?? Bundle.main.object(forInfoDictionaryKey: "ScotchProbeRuntimeFeed") as! String
        let container = ScotchContainer(bundleIdentifier: Bundle.main.bundleIdentifier!, runtimeFeedURL: URL(string: runtimeFeed)!)
        do {
            try FileManager.default.createDirectory(at: container.paths.applicationSupportDirectory, withIntermediateDirectories: true)
            let settings: [String: Any] = ["killProcessesOnTerminate": true, "checkRuntimeUpdates": false, "defaultBottleDirectoryPath": container.paths.defaultBottlesDirectory.path]
            if !FileManager.default.fileExists(atPath: container.paths.settingsURL.path) {
                try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: container.paths.settingsURL)
            }
        } catch { fatalError(error.localizedDescription) }
        let delegate = ScotchAppDelegate()
        ScotchAppDelegate.sharedContainer = container
        app.delegate = delegate
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 20, height: 20), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        let updater = ScotchAppUpdater(container: container)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { updater.update() }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let text = updater.appStatus + "\n" + updater.runtimeStatus
                try? Data(text.utf8).write(to: marker.appendingPathExtension("status"), options: .atomic)
                if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2", !updater.isWorking,
                   updater.appStatus.hasPrefix("No newer compatible"), updater.runtimeStatus == "No newer approved runtime available." {
                    try? Data("Updated app relaunched; both feeds checked; no repeated update".utf8).write(to: marker, options: .atomic)
                    app.terminate(nil)
                }
            }
        }
        withExtendedLifetime((updater, delegate, timer, window)) { app.run() }
    }
}
