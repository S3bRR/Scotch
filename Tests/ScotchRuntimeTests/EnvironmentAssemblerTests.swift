import Foundation
import Testing
@testable import ScotchDomain
@testable import ScotchInfrastructure
@testable import ScotchRuntime

struct EnvironmentAssemblerTests {
    @Test func dxvkEnvironmentIncludesExpectedKeys() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxvk
        settings.backend.dxvkAsync = true
        settings.backend.dxvkHud = .fps

        let bottle = BottleSummary(
            id: BottleID(rawValue: "test"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)

        #expect(env["WINEPREFIX"] == "/tmp/test-bottle")
        #expect(env["DXVK_ASYNC"] == "1")
        #expect(env["DXVK_HUD"] == "fps")
        #expect(env["WINEDLLOVERRIDES"] == "dxgi,d3d9,d3d10core,d3d11=n,b")
    }

    @Test func steamBuiltinOpenGLSuppressesPrimaryZinkDllOverride() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .zink
        settings.backend.glZinkEnabled = true
        settings.backend.steamBuiltinOpenGL = true

        let bottle = BottleSummary(
            id: BottleID(rawValue: "steam-zink"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-zink"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)

        #expect(env["WINEDLLOVERRIDES"] == nil)
        #expect(env["GALLIUM_DRIVER"] == "zink")
        #expect(env["MESA_LOADER_DRIVER_OVERRIDE"] == "zink")
    }

    @Test func additiveZinkDllOverrideOnlyAppliesWhenSteamBuiltinDisabled() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxvk
        settings.backend.glZinkEnabled = true
        settings.backend.steamBuiltinOpenGL = false

        let bottle = BottleSummary(
            id: BottleID(rawValue: "additive-zink"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-dxvk"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)
        #expect(env["WINEDLLOVERRIDES"] == "dxgi,d3d9,d3d10core,d3d11=n,b;opengl32,libgallium_wgl,libglapi=n,b")

        settings.backend.steamBuiltinOpenGL = true
        let steamEnv = assembler.makeWineEnvironment(
            bottle: BottleSummary(
                id: bottle.id,
                directoryURL: bottle.directoryURL,
                settings: settings,
                isAvailable: bottle.isAvailable
            )
        )
        #expect(steamEnv["WINEDLLOVERRIDES"] == "dxgi,d3d9,d3d10core,d3d11=n,b")
    }

    @Test func metalBackendsDoNotSetMoltenVKFlagsWithoutZink() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxmt
        settings.backend.glZinkEnabled = false

        let dxmtBottle = BottleSummary(
            id: BottleID(rawValue: "dxmt"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-dxmt"),
            settings: settings,
            isAvailable: true
        )

        let dxmtEnv = assembler.makeWineEnvironment(bottle: dxmtBottle)
        #expect(dxmtEnv["MVK_CONFIG_RESUME_LOST_DEVICE"] == nil)
        #expect(dxmtEnv["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] == nil)

        settings.backend.backend = .d3dmetal
        let d3dBottle = BottleSummary(
            id: BottleID(rawValue: "d3dmetal"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-d3dmetal"),
            settings: settings,
            isAvailable: true
        )

        let d3dEnv = assembler.makeWineEnvironment(bottle: d3dBottle)
        #expect(d3dEnv["MVK_CONFIG_RESUME_LOST_DEVICE"] == nil)
        #expect(d3dEnv["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] == nil)
    }

    @Test func additiveZinkOnDXMTSetsMoltenVKAndOpenGLFlags() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxmt
        settings.backend.glZinkEnabled = true
        settings.backend.steamBuiltinOpenGL = false

        let bottle = BottleSummary(
            id: BottleID(rawValue: "dxmt-zink"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-dxmt-zink"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)
        #expect(env["GALLIUM_DRIVER"] == "zink")
        #expect(env["MESA_LOADER_DRIVER_OVERRIDE"] == "zink")
        #expect(env["WINEDLLOVERRIDES"] == "dxgi,d3d10core,d3d11,winemetal=n,b;opengl32,libgallium_wgl,libglapi=n,b")
        #expect(env["MVK_CONFIG_RESUME_LOST_DEVICE"] == "1")
        #expect(env["MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE"] == "1")
    }

    @Test func gpuSpoofExportsExpectedEnvironmentWhenEnabled() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxvk
        settings.gpu.spoofPreset = .nvidiaRTX3080
        settings.gpu.deviceIdSalt = 0

        let bottle = BottleSummary(
            id: BottleID(rawValue: "gpu-spoof"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-gpu-spoof"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)
        #expect(env["SCOTCH_GPU_SPOOF_LIB"] == paths.librariesDirectory.appending(path: "VulkanSpoof/libscotch_gpu_spoof.dylib").path(percentEncoded: false))
        #expect(env["SCOTCH_GPU_VENDOR_ID"] == "10de")
        #expect(env["SCOTCH_GPU_DEVICE_ID"] == "2206")
        #expect(env["SCOTCH_GPU_DEVICE_NAME"] == "NVIDIA GeForce RTX 3080")
        #expect(env["SCOTCH_GPU_VRAM_MB"] == "10240")
        #expect(env["SCOTCH_REAL_MOLTENVK_PATH"] == paths.librariesDirectory.appending(path: "Wine/lib/libMoltenVK.dylib").path(percentEncoded: false))
        #expect(env["DXVK_CONFIG_FILE"] == "/tmp/test-bottle-gpu-spoof/dxvk.conf")
    }

    @Test func gpuSpoofDoesNotExportVariablesWhenDisabled() async throws {
        let paths = AppPaths(bundleIdentifier: "com.s3brr.Scotch.Test")
        let assembler = EnvironmentAssembler(paths: paths)

        var settings = BottleSettings()
        settings.backend.backend = .dxvk
        settings.gpu.spoofPreset = .off

        let bottle = BottleSummary(
            id: BottleID(rawValue: "gpu-off"),
            directoryURL: URL(fileURLWithPath: "/tmp/test-bottle-gpu-off"),
            settings: settings,
            isAvailable: true
        )

        let env = assembler.makeWineEnvironment(bottle: bottle)
        #expect(env["SCOTCH_GPU_SPOOF_LIB"] == nil)
        #expect(env["SCOTCH_GPU_VENDOR_ID"] == nil)
        #expect(env["SCOTCH_GPU_DEVICE_ID"] == nil)
        #expect(env["SCOTCH_GPU_DEVICE_NAME"] == nil)
        #expect(env["SCOTCH_GPU_VRAM_MB"] == nil)
        #expect(env["SCOTCH_REAL_MOLTENVK_PATH"] == nil)
        #expect(env["DXVK_CONFIG_FILE"] == nil)
    }
}
