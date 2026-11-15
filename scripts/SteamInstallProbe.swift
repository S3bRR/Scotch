import Foundation
import ScotchDomain
import ScotchInfrastructure
import ScotchRuntime
import ScotchFeatures

/// Opt-in live network check. Only a uniquely named application ID and copies
/// of runtime files are used; no account login or existing bottle is opened.
@main struct SteamInstallProbe {
    @MainActor static func main() async {
        let resume = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--resume"
        let installOnly = CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--install-only"
        let id = resume ? CommandLine.arguments[2] : "com.s3brr.Scotch.SteamInstallProbe.\(UUID().uuidString)"
        guard id.hasPrefix("com.s3brr.Scotch.SteamInstallProbe."), !id.contains("/"), !id.contains("..") else { fatalError("Disposable roots only") }
        let paths = AppPaths(bundleIdentifier: id)
        var container: ScotchContainer?
        var bottle: BottleSummary?
        do {
            if !resume {
                guard CommandLine.arguments.count == 2 || installOnly else { throw ProbeError("Pass an installed Libraries directory to copy") }
                let source = URL(fileURLWithPath: CommandLine.arguments[installOnly ? 2 : 1])
                try FileManager.default.createDirectory(at: paths.applicationSupportDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: paths.librariesDirectory)
            }
            let services = ScotchContainer(bundleIdentifier: id)
            container = services
            if await services.runtimeInstaller.needsGraphicsRepair() { try await services.runtimeInstaller.repairGraphics() }
            var fresh: BottleSummary
            if resume {
                guard let existing = await services.bottleRepository.loadBottles().first else { throw ProbeError("Missing disposable bottle") }
                fresh = existing; bottle = fresh
            } else {
                fresh = try await services.bottleRepository.prepareBottle(name: "Steam fresh install test", windowsVersion: .win10, containerURL: paths.defaultBottlesDirectory)
                bottle = fresh
                fresh = try await services.bottleRepository.setupWineEnvironment(fresh, progress: nil)
                // Complete the same metadata/catalog publication normally performed
                // after the optional core-font step, without another font download.
                try await services.plistStore.write(fresh.settings, to: fresh.directoryURL.appending(path: BottleSettings.metadataFileName))
                fresh.inFlight = false
                fresh.isAvailable = true
                bottle = fresh
                try await services.plistStore.write(BottleCatalog(bottlePaths: [fresh.directoryURL.path]), to: paths.bottleCatalogURL)
                _ = await services.bottleRepository.loadBottles()
                let model = BottleDetailViewModel(container: services, bottle: fresh)
                let installStarted = Date()
                await model.installSteam()
                guard model.steamInstalled, !model.isInstallingSteam, model.steamInstallProgress == 1,
                      model.bottle.settings.info.pins.contains(where: { $0.name == "Steam" }) else {
                    throw ProbeError(model.statusMessage ?? "Install Steam did not finish")
                }
                fresh = model.bottle; bottle = fresh
                say("Passed: real Install Steam action completes and pins Steam after the installer exits")
                try await waitForSignIn(fresh, started: installStarted)
                try await checkWineLog(services, bottle: fresh)
                say("Passed: fresh first launch downloads the client and reaches sign-in without a runtime switch or manual restart")
            }
            let steamExecutable = fresh.directoryURL.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe")
            var steamSettings = try ProgramSettingsFiles.load(for: steamExecutable, in: fresh.directoryURL)
            steamSettings.environment["WINEDEBUG"] = "fixme-all,+macdrv_d3dmtl,+win"
            try await ProgramSettingsFiles.save(steamSettings, for: steamExecutable, in: fresh.directoryURL)
            let backends: [TranslationBackend] = installOnly ? [] : [.dxvk, .dxmt, .d3dmetal, .zink]
            for backend in backends {
                await services.runtimeService.killBottle(fresh, timeout: 15)
                var settings = fresh.settings; settings.backend.backend = backend
                try await services.bottleRepository.saveSettings(settings, for: fresh.id)
                fresh.settings = settings; bottle = fresh
                let started = Date()
                let cefFile = fresh.directoryURL.appending(path: "drive_c/Program Files (x86)/Steam/logs/cef_log.txt")
                let cefOffset = (try? Data(contentsOf: cefFile).count) ?? 0
                try await services.runtimeService.runSteam(in: fresh, arguments: [])
                try await waitForSignIn(fresh, started: started, cefOffset: cefOffset)
                try await checkWineLog(services, bottle: fresh)
                say("Passed: Steam reaches sign-in with \(backend.displayName); no Chromium GPU crash loop")
            }
            await services.runtimeService.killBottle(fresh, timeout: 15)
            say(installOnly ? "Passed: fresh Steam installation, pin, first bootstrap and GPU compositing" : "Passed: Steam installation, pin, first bootstrap, and all four graphics backend launches")
        } catch {
            if let services = container, let bottle { await services.runtimeService.killBottle(bottle, timeout: 15) }
            say("Steam install check failed: \(error.localizedDescription)")
            say("Disposable diagnostics retained at \(paths.applicationSupportDirectory.path)")
            exit(1)
        }
        say("Disposable diagnostics retained at \(paths.applicationSupportDirectory.path)")
    }

    static func checkWineLog(_ services: ScotchContainer, bottle: BottleSummary) async throws {
        guard let file = await services.runtimeService.latestLogURL(for: bottle),
              let text = try? String(contentsOf: file, encoding: .utf8) else { throw ProbeError("Missing Steam launch diagnostics") }
        guard !text.contains("Unhandled exception"), !text.contains("starting debugger") else {
            throw ProbeError("Steam's web helper entered WineDbg")
        }
    }

    static func waitForSignIn(_ bottle: BottleSummary, started: Date, cefOffset: Int = 0) async throws {
        let steam = bottle.directoryURL.appending(path: "drive_c/Program Files (x86)/Steam")
        let login = steam.appending(path: "logs/steamui_login.txt")
        let cef = steam.appending(path: "logs/cef_log.txt")
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            let text = (try? String(contentsOf: login, encoding: .utf8)) ?? ""
            // URL resource values cache their first result. Read fresh file
            // attributes after every Steam restart instead of an old timestamp.
            let attributes = try? FileManager.default.attributesOfItem(atPath: login.path)
            let modified = attributes?[.modificationDate] as? Date ?? .distantPast
            let webhelper = (try? String(contentsOf: steam.appending(path: "logs/webhelper.txt"), encoding: .utf8)) ?? ""
            let current = webhelper.components(separatedBy: "Startup - webhelper launched").last ?? ""
            let softwareGPU = current.range(of: #"(?:^|\s)--disable-gpu(?:\s|$)"#, options: .regularExpression) != nil
            if modified >= started && text.contains("WaitingForCredentials - OK") && !softwareGPU && !current.contains("--single-process") {
                try await Task.sleep(for: .seconds(10))
                let data = (try? Data(contentsOf: cef)) ?? Data()
                let errors = String(decoding: data.dropFirst(data.count >= cefOffset ? cefOffset : 0), as: UTF8.self)
                guard !errors.contains("GPU process has crashed"), !errors.contains("Renderer11.cpp"), !errors.contains("FATAL:") else {
                    throw ProbeError("Steam's CEF renderer reported a GPU failure")
                }
                let gpu = try String(contentsOf: steam.appending(path: "logs/webhelper_gpu.txt"), encoding: .utf8)
                let compositing = gpu.split(separator: "\n").last(where: { $0.contains("[ gpu_compositing ]") }) ?? ""
                guard compositing.contains(": enabled") else { throw ProbeError("Steam did not enable GPU compositing") }
                let helper = steam.appending(path: "bin/cef/cef.win64/steamwebhelper.exe")
                guard FileManager.default.fileExists(atPath: helper.path) else {
                    throw ProbeError("Steam's original helper is missing")
                }
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw ProbeError("Steam did not finish its first-run update and reach sign-in within five minutes")
    }
}
private struct ProbeError: LocalizedError { let errorDescription: String?; init(_ text: String) { errorDescription = text } }
private func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
