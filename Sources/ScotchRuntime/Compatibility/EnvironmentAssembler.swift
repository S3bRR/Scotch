import Foundation
import ScotchDomain
import ScotchInfrastructure

public struct EnvironmentAssembler {
    private let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func makeWineEnvironment(
        bottle: BottleSummary,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var environment: [String: String] = [
            "WINEPREFIX": bottle.directoryURL.path(percentEncoded: false),
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1",
            "WINE": paths.wineBinaryURL.path(percentEncoded: false),
            "WINELOADER": paths.wineBinaryURL.path(percentEncoded: false),
            "WINESERVER": paths.wineServerBinaryURL.path(percentEncoded: false),
            "W_CACHE": paths.winetricksCacheDirectory.path(percentEncoded: false)
        ]

        let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(paths.runtimeBinDirectory.path(percentEncoded: false)):\(originalPath)"

        applyCompatibilityEnvironment(settings: bottle.settings, environment: &environment)

        if let identity = bottle.settings.resolvedGPUIdentity() {
            let shimPath = paths.librariesDirectory
                .appending(path: "VulkanSpoof")
                .appending(path: "libscotch_gpu_spoof.dylib")
                .path(percentEncoded: false)
            environment["SCOTCH_GPU_SPOOF_LIB"] = shimPath
            environment["SCOTCH_GPU_VENDOR_ID"] = String(identity.vendorId, radix: 16)
            environment["SCOTCH_GPU_DEVICE_ID"] = String(identity.deviceId, radix: 16)
            environment["SCOTCH_GPU_DEVICE_NAME"] = identity.description
            environment["SCOTCH_GPU_VRAM_MB"] = String(identity.vramMB)
            environment["SCOTCH_REAL_MOLTENVK_PATH"] = paths.librariesDirectory
                .appending(path: "Wine/lib/libMoltenVK.dylib")
                .path(percentEncoded: false)
            environment["DXVK_VENDOR_ID"] = String(format: "%x", identity.vendorId)
            environment["DXVK_DEVICE_ID"] = String(format: "%x", identity.deviceId)

            if bottle.settings.backend.backend == .dxvk {
                environment["DXVK_CONFIG_FILE"] = bottle.directoryURL
                    .appending(path: "dxvk.conf")
                    .path(percentEncoded: false)
            }
        }

        environment.merge(extra, uniquingKeysWith: { _, new in new })
        return environment
    }

    public func makeWineServerEnvironment(
        bottle: BottleSummary,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var environment = makeWineEnvironment(bottle: bottle, extra: extra)
        environment.merge(extra, uniquingKeysWith: { _, new in new })
        return environment
    }

    public func makeShellEnvironment(bottle: BottleSummary) -> [String: String] {
        var environment = makeWineEnvironment(bottle: bottle)
        environment["WINE"] = "wine"
        return environment
    }

    public func launchEnvironmentFileContents(_ environment: [String: String]) -> String {
        environment
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard key.isShellEnvironmentKey, let value = environment[key] else { return nil }
                return "export \(key)=\(value.shellQuoted)"
            }
            .joined(separator: "\n")
            + "\n"
    }

    private func applyCompatibilityEnvironment(settings: BottleSettings, environment: inout [String: String]) {
        var overrides: [String] = []
        let backend = settings.backend.backend
        let zinkActive = backend == .zink || settings.backend.glZinkEnabled
        let steamBuiltinOpenGLActive = settings.backend.steamBuiltinOpenGL && zinkActive

        if let baseline = backend.wineDLLOverrides, !(steamBuiltinOpenGLActive && backend == .zink) {
            overrides.append(baseline)
        }

        if backend == .dxvk {
            switch settings.backend.dxvkHud {
            case .full:
                environment["DXVK_HUD"] = "full"
            case .partial:
                environment["DXVK_HUD"] = "devinfo,fps,frametimes"
            case .fps:
                environment["DXVK_HUD"] = "fps"
            case .off:
                break
            }
            if settings.backend.dxvkAsync {
                environment["DXVK_ASYNC"] = "1"
            }
        }

        if zinkActive {
            environment["GALLIUM_DRIVER"] = "zink"
            environment["MESA_LOADER_DRIVER_OVERRIDE"] = "zink"
            environment["LIBGL_ALWAYS_SOFTWARE"] = "0"
        }

        if settings.backend.glZinkEnabled && backend != .zink && !steamBuiltinOpenGLActive {
            overrides.append("opengl32,libgallium_wgl,libglapi=n,b")
        }

        if !overrides.isEmpty {
            environment["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")
        }

        switch settings.wine.enhancedSync {
        case .none:
            break
        case .esync:
            environment["WINEESYNC"] = "1"
        case .msync:
            environment["WINEMSYNC"] = "1"
            environment["WINEESYNC"] = "1"
        }

        if settings.wine.avxEnabled {
            environment["ROSETTA_ADVERTISE_AVX"] = "1"
        }
        if settings.metal.metalHud {
            environment["MTL_HUD_ENABLED"] = "1"
        }
        if settings.metal.metalTrace {
            environment["METAL_CAPTURE_ENABLED"] = "1"
        }
        if settings.metal.dxrEnabled {
            environment["D3DM_SUPPORT_DXR"] = "1"
        }

        if backend == .dxvk || zinkActive {
            environment["MVK_CONFIG_RESUME_LOST_DEVICE"] = "1"
            environment["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] = "1"
        }
    }
}
