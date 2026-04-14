import SwiftUI
import AppKit
import ScotchFeatures

@main
struct ScotchAppMain: App {
    private let container = ScotchContainer(bundleIdentifier: "com.s3brr.Scotch")
    @NSApplicationDelegateAdaptor(ScotchAppDelegate.self) private var appDelegate
    @Environment(\.openURL) private var openURL

    init() {
        ScotchAppDelegate.sharedContainer = container
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .frame(minWidth: 980, minHeight: 600)
                .background(PersistentWindowGlass().ignoresSafeArea(.all))
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open Setup") {
                    NotificationCenter.default.post(name: .scotchOpenSetup, object: nil)
                }
                Button("Settings…") {
                    NotificationCenter.default.post(name: .scotchOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
                Button("Diagnostics…") {
                    NotificationCenter.default.post(name: .scotchOpenDiagnostics, object: nil)
                }
                Button("Install Command Line Tool") {
                    Task {
                        let result = await CommandLineInstaller.install()
                        let message: String
                        switch result {
                        case .success:
                            message = "Installed `scotch` command line tool. Run `scotch help` in a new terminal."
                        case .failure(let error):
                            message = error.localizedDescription
                        }
                        NotificationCenter.default.post(name: .scotchCLIInstallResult, object: message)
                    }
                }
            }

            CommandGroup(after: .newItem) {
                Button("Open Existing Bottle") {
                    NotificationCenter.default.post(name: .scotchOpenExistingBottle, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])
            }

            CommandGroup(after: .importExport) {
                Button("Open Logs") {
                    NotificationCenter.default.post(name: .scotchOpenLogs, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Kill Bottles") {
                    NotificationCenter.default.post(name: .scotchKillBottles, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Clear Shader Cache") {
                    NotificationCenter.default.post(name: .scotchClearShaderCaches, object: nil)
                }
            }

            CommandGroup(replacing: .help) {
                Button("Scotch on GitHub") {
                    if let url = URL(string: "https://github.com/S3bRR/Scotch") {
                        openURL(url)
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
