import Foundation
import CryptoKit
import ScotchDomain
import ScotchInfrastructure

public struct PreparedProgramGraphics: Sendable {
    public let bottle: BottleSummary
    public let lease: UpdateLease
    public let choice: ProgramGraphicsChoice?
}

public struct ProgramGraphicsManager: Sendable {
    let paths: AppPaths
    let activity: UpdateActivity
    private let availabilityCheck: (@Sendable (TranslationBackend, WindowsArchitecture, BottleSummary) -> String?)?
    public init(paths: AppPaths, activity: UpdateActivity = .shared, availabilityCheck: (@Sendable (TranslationBackend, WindowsArchitecture, BottleSummary) -> String?)? = nil) {
        self.paths = paths; self.activity = activity; self.availabilityCheck = availabilityCheck
    }

    public func recommendation(for executable: URL, bottle: BottleSummary, settings: ProgramSettings) async -> ProgramGraphicsRecommendation {
        let analysis = await Task.detached(priority: .userInitiated) { ExecutableGraphicsInspector.inspect(executable) }.value
        return recommend(analysis, executable: executable, bottle: bottle, settings: settings)
    }

    public func recommend(_ analysis: ExecutableGraphicsAnalysis, executable: URL, bottle: BottleSummary, settings: ProgramSettings) -> ProgramGraphicsRecommendation {
        let mode = settings.graphicsMode.resolved(in: bottle.settings.backend)
        let runtime = runtimeFingerprint(bottle)
        var result = ProgramGraphicsRecommendation(analysis: analysis, backend: nil, automatic: false, reason: analysis.explanation, availabilityIssue: nil, remembered: false, currentBackend: bottle.settings.backend.backend, usesAuto: mode == .automatic)
        let customGraphics = Set(["WINEDLLOVERRIDES", "WINEDLLPATH", "GRAPHICS_BACKEND", "WINE_D3D_CONFIG", "GALLIUM_DRIVER", "VK_DRIVER_FILES", "VK_ICD_FILENAMES"])
        if mode == .manual {
            result.backend = settings.manualBackend; result.automatic = true
            result.reason = "Your manual choice takes priority over detection and remembered choices."
        } else if mode == .automatic, let confirmed = settings.confirmedGraphics,
                  !analysis.fingerprint.isEmpty, confirmed.executableFingerprint == analysis.fingerprint,
                  !analysis.limited, confirmed.runtimeFingerprint == runtime,
                  confirmed.configurationFingerprint == configurationFingerprint(bottle, arguments: settings.parsedArguments(), environment: settings.effectiveEnvironment()) {
            result.backend = confirmed.backend; result.automatic = true; result.remembered = true
            result.reason = "Using the setup you confirmed working for this application and runtime."
        } else {
            if mode == .automatic, !customGraphics.isDisjoint(with: settings.environment.keys) {
                result.reason = "Custom graphics environment variables control this application. Keep the bottle setting or choose a backend manually."
                return result
            }
            let name = executable.deletingPathExtension().lastPathComponent.lowercased()
            let launcher = ["steam", "steamsetup", "setup", "install", "epicgameslauncher", "battle.net", "galaxyclient"].contains(name) || name.contains("launcher")
            let supported = analysis.architecture == .x86 || analysis.architecture == .x64
            if !supported || analysis.limited || launcher || analysis.apis.count != 1 {
                result.reason = launcher ? "This is a launcher or installer. Its graphics imports do not identify the game it will launch. Keep the bottle setting." : analysis.explanation + " No high-confidence automatic choice is available; keep the bottle setting."
            } else if analysis.apis == [.d3d12], analysis.architecture == .x64 {
                result.backend = .d3dmetal; result.automatic = true
                result.reason = "64-bit DirectX 12 detected. D3DMetal is Scotch's installed DirectX 12 backend. Performance has not been measured."
            } else if analysis.apis == [.openGL] {
                result.backend = .zink; result.automatic = true
                result.reason = "OpenGL detected. Zink is Scotch's OpenGL translation backend. The required OpenGL version is not known from imports."
            } else if !analysis.apis.isDisjoint(with: [.d3d10, .d3d11]) {
                let current = bottle.settings.backend.backend
                result.backend = [.dxvk, .dxmt].contains(current) || (current == .d3dmetal && analysis.architecture == .x64 && analysis.apis == [.d3d11]) ? current : .dxvk
                result.reason = "DirectX 10/11 detected. Several backends can support it; keep a working bottle setup or test this recommendation. Auto will not guess which is fastest."
            } else {
                result.reason = "The detected API has no high-confidence automatic mapping in this Scotch build. Keep the bottle setting."
            }
            if mode == .automatic, settings.confirmedGraphics != nil, !result.remembered {
                result.reason += " The application, runtime or launch settings changed, so its old confirmation is retained but is not being reused."
            }
        }
        if let backend = result.backend {
            result.availabilityIssue = availabilityIssue(backend, architecture: analysis.architecture, bottle: bottle)
        }
        return result
    }

    public func prepareLaunch(_ executable: URL, bottle original: BottleSummary, arguments: [String] = [], environment: [String: String] = [:]) async throws -> PreparedProgramGraphics {
        // Reload persisted settings: another application may have selected a
        // different bottle-wide backend since the view or CLI loaded its model.
        var bottle = original
        bottle.settings = try await PlistStore().read(BottleSettings.self, from: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
        var settings = try ProgramSettingsFiles.load(for: executable, in: bottle.directoryURL)
        if configurationFingerprint(bottle, arguments: arguments, environment: environment) != configurationFingerprint(bottle, arguments: settings.parsedArguments(), environment: settings.effectiveEnvironment()) {
            settings.confirmedGraphics = nil
        }
        if settings.graphicsMode.resolved(in: bottle.settings.backend) == .bottle {
            return PreparedProgramGraphics(bottle: bottle, lease: try await unchangedLaunchLease(bottle), choice: nil)
        }
        var decisionSettings = settings
        decisionSettings.environment = environment
        let recommendation = await recommendation(for: executable, bottle: bottle, settings: decisionSettings)
        guard recommendation.automatic, let backend = recommendation.backend else {
            return PreparedProgramGraphics(bottle: bottle, lease: try await unchangedLaunchLease(bottle), choice: nil)
        }
        if let issue = recommendation.availabilityIssue {
            throw RuntimeInstallerError.installFailed(issue + " Your application profile and bottle have been preserved.")
        }
        let zink = recommendation.remembered ? settings.confirmedGraphics!.zinkEnabled : bottle.settings.backend.glZinkEnabled
        let lease: UpdateLease
        if backend != bottle.settings.backend.backend || zink != bottle.settings.backend.glZinkEnabled {
            (bottle, lease) = try await BottleRuntimeManager(paths: paths, activity: activity).selectForProgramLaunch(bottle, backend: backend, zinkEnabled: zink)
        } else { lease = try await unchangedLaunchLease(bottle) }
        let choice = ProgramGraphicsChoice(backend: backend, zinkEnabled: zink, executableFingerprint: recommendation.analysis.fingerprint, runtimeFingerprint: runtimeFingerprint(bottle), configurationFingerprint: configurationFingerprint(bottle, arguments: arguments, environment: environment))
        return PreparedProgramGraphics(bottle: bottle, lease: lease, choice: choice)
    }

    private func unchangedLaunchLease(_ bottle: BottleSummary) async throws -> UpdateLease {
        let lease = try activity.beginOperation()
        let current = try await PlistStore().read(BottleSettings.self, from: bottle.directoryURL.appending(path: BottleSettings.metadataFileName))
        guard current == bottle.settings else { throw RuntimeUpdateError.invalid("Bottle settings changed. Launch the application again.") }
        return lease
    }

    public func recordLaunch(_ executable: URL, bottle: BottleSummary, choice: ProgramGraphicsChoice?, arguments: [String] = [], environment: [String: String] = [:]) async throws {
        var settings = try ProgramSettingsFiles.load(for: executable, in: bottle.directoryURL)
        var launched = choice
        if launched == nil {
            let analysis = await Task.detached { ExecutableGraphicsInspector.inspect(executable) }.value
            if !analysis.fingerprint.isEmpty {
                launched = ProgramGraphicsChoice(backend: bottle.settings.backend.backend, zinkEnabled: bottle.settings.backend.glZinkEnabled, executableFingerprint: analysis.fingerprint, runtimeFingerprint: runtimeFingerprint(bottle), configurationFingerprint: configurationFingerprint(bottle, arguments: arguments, environment: environment))
            }
        }
        settings.lastGraphicsLaunch = launched
        try await ProgramSettingsFiles.save(settings, for: executable, in: bottle.directoryURL)
    }

    public func confirmWorking(_ executable: URL, bottle: BottleSummary, settings: ProgramSettings) async throws -> ProgramSettings {
        let persisted = try ProgramSettingsFiles.load(for: executable, in: bottle.directoryURL)
        let analysis = await Task.detached { ExecutableGraphicsInspector.inspect(executable) }.value
        guard let launched = persisted.lastGraphicsLaunch, !analysis.fingerprint.isEmpty,
              launched.executableFingerprint == analysis.fingerprint, launched.runtimeFingerprint == runtimeFingerprint(bottle),
              launched.configurationFingerprint == configurationFingerprint(bottle, arguments: settings.parsedArguments(), environment: settings.effectiveEnvironment()) else {
            throw RuntimeInstallerError.installFailed("Launch this application with the current runtime, check that it works, then remember its setup.")
        }
        var changed = settings
        changed.confirmedGraphics = launched
        changed.lastGraphicsLaunch = launched
        if changed.graphicsMode == .bottle { changed.graphicsMode = .automatic }
        try await ProgramSettingsFiles.save(changed, for: executable, in: bottle.directoryURL)
        return changed
    }

    public func runtimeFingerprint(_ bottle: BottleSummary) -> String {
        let selected = paths.forBottle(bottle).librariesDirectory
        var data = Data((selected.path + ":" + GraphicsSupportInstallation.version + ":" + (bottle.settings.runtimeSetID ?? "original")).utf8)
        for file in [RuntimeManifest.fileName, "Graphics/Version", "Graphics/Sources.json"] {
            if let bytes = try? Data(contentsOf: selected.appending(path: file)), bytes.count < 1_000_000 { data.append(bytes) }
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func configurationFingerprint(_ bottle: BottleSummary, arguments: [String], environment: [String: String]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var bytes = (try? encoder.encode(arguments)) ?? Data()
        bytes.append((try? encoder.encode(environment)) ?? Data())
        bytes.append((try? encoder.encode(bottle.settings.wine)) ?? Data())
        bytes.append((try? encoder.encode(bottle.settings.gpu)) ?? Data())
        bytes.append((try? encoder.encode(bottle.settings.metal)) ?? Data())
        bytes.append((try? encoder.encode(["dxvkAsync": String(bottle.settings.backend.dxvkAsync), "dxvkHUD": bottle.settings.backend.dxvkHud.rawValue, "steamBuiltinOpenGL": String(bottle.settings.backend.steamBuiltinOpenGL)])) ?? Data())
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public func availabilityIssue(_ backend: TranslationBackend, architecture: WindowsArchitecture, bottle: BottleSummary) -> String? {
        if let availabilityCheck { return availabilityCheck(backend, architecture, bottle) }
        let libraries = paths.forBottle(bottle).librariesDirectory
        let suffix = architecture == .x86 ? "x32" : "x64"
        do {
            try MetalEngineInstallation.verify(in: libraries)
            try MetalEngineInstallation.verifyDXMT(in: libraries)
            try GraphicsSupportInstallation.verify(in: libraries)
            switch backend {
            case .d3dmetal:
                guard architecture != .x86 && architecture != .unsupported else { return "D3DMetal supports 64-bit x86 applications in this build." }
                try D3DMetalInstallation.verify(at: libraries.appending(path: "D3DMetal"))
                try MetalEngineInstallation.verify(in: libraries)
                try GraphicsSupportInstallation.verify(in: libraries)
            case .dxmt:
                try MetalEngineInstallation.verify(in: libraries)
                try MetalEngineInstallation.verifyDXMT(in: libraries)
                try GraphicsSupportInstallation.verify(in: libraries)
            case .zink:
                try GraphicsSupportInstallation.verify(in: libraries)
                try PackageArchitecture.verifyPE(at: libraries.appending(path: "Zink/\(suffix)/opengl32.dll"), machine: architecture == .x86 ? 0x14c : 0x8664)
            case .dxvk:
                try GraphicsSupportInstallation.verify(in: libraries)
                try PackageArchitecture.verifyPE(at: libraries.appending(path: "DXVK/\(suffix)/d3d11.dll"), machine: architecture == .x86 ? 0x14c : 0x8664)
            case .none: break
            }
            var configured = bottle; configured.settings.backend.backend = backend
            guard FileManager.default.fileExists(atPath: paths.forBottle(configured).wineBinaryURL.path) else { return "The selected Wine engine is missing. Use Update to repair it." }
            return nil
        } catch { return "\(backend.displayName) is unavailable or needs repair: \(error.localizedDescription) Use Update." }
    }
}
