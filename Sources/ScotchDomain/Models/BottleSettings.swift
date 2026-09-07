import Foundation

public struct PinnedProgram: Codable, Hashable, Sendable {
    public var name: String
    public var executablePath: String
    public var removable: Bool

    public init(name: String, executablePath: String, removable: Bool = false) {
        self.name = name
        self.executablePath = executablePath
        self.removable = removable
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case executablePath
        case removable
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        removable = try container.decodeIfPresent(Bool.self, forKey: .removable) ?? false

        if let path = try? container.decodeIfPresent(String.self, forKey: .executablePath) {
            executablePath = path
        } else if let legacyURL = try? container.decodeIfPresent(URL.self, forKey: .url) {
            executablePath = legacyURL.path(percentEncoded: false)
        } else {
            executablePath = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(executablePath, forKey: .executablePath)
        try container.encode(removable, forKey: .removable)
    }
}

public struct BottleInfo: Codable, Equatable, Sendable {
    public var name: String
    public var pins: [PinnedProgram]
    public var blocklist: [String]

    public init(name: String = "Bottle", pins: [PinnedProgram] = [], blocklist: [String] = []) {
        self.name = name
        self.pins = pins
        self.blocklist = blocklist
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case pins
        case blocklist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Bottle"
        pins = try container.decodeIfPresent([PinnedProgram].self, forKey: .pins) ?? []

        if let blocklist = try? container.decodeIfPresent([String].self, forKey: .blocklist) {
            self.blocklist = blocklist
        } else if let legacyBlocklist = try? container.decodeIfPresent([URL].self, forKey: .blocklist) {
            self.blocklist = legacyBlocklist.map { $0.path(percentEncoded: false) }
        } else {
            self.blocklist = []
        }
    }
}

public struct BottleWineConfig: Codable, Equatable, Sendable {
    public var wineVersion: AppVersion
    public var windowsVersion: WindowsVersion
    public var enhancedSync: EnhancedSyncMode
    public var avxEnabled: Bool

    public init(
        wineVersion: AppVersion = AppVersion(11, 16, 0),
        windowsVersion: WindowsVersion = .win10,
        enhancedSync: EnhancedSyncMode = .msync,
        avxEnabled: Bool = false
    ) {
        self.wineVersion = wineVersion
        self.windowsVersion = windowsVersion
        self.enhancedSync = enhancedSync
        self.avxEnabled = avxEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case wineVersion
        case windowsVersion
        case enhancedSync
        case avxEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wineVersion = try container.decodeIfPresent(AppVersion.self, forKey: .wineVersion) ?? AppVersion(11, 0, 0)
        windowsVersion = try container.decodeIfPresent(WindowsVersion.self, forKey: .windowsVersion) ?? .win10
        enhancedSync = try container.decodeIfPresent(EnhancedSyncMode.self, forKey: .enhancedSync) ?? .msync
        avxEnabled = try container.decodeIfPresent(Bool.self, forKey: .avxEnabled) ?? false
    }
}

public struct BottleMetalConfig: Codable, Equatable, Sendable {
    public var metalHud: Bool
    public var metalTrace: Bool
    public var dxrEnabled: Bool

    public init(metalHud: Bool = false, metalTrace: Bool = false, dxrEnabled: Bool = false) {
        self.metalHud = metalHud
        self.metalTrace = metalTrace
        self.dxrEnabled = dxrEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case metalHud
        case metalTrace
        case dxrEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metalHud = try container.decodeIfPresent(Bool.self, forKey: .metalHud) ?? false
        metalTrace = try container.decodeIfPresent(Bool.self, forKey: .metalTrace) ?? false
        dxrEnabled = try container.decodeIfPresent(Bool.self, forKey: .dxrEnabled) ?? false
    }
}

public struct BottleBackendConfig: Codable, Equatable, Sendable {
    public var backend: TranslationBackend
    public var dxvkAsync: Bool
    public var dxvkHud: DXVKHUD
    public var glZinkEnabled: Bool
    public var steamBuiltinOpenGL: Bool

    public init(
        backend: TranslationBackend = .dxvk,
        dxvkAsync: Bool = true,
        dxvkHud: DXVKHUD = .off,
        glZinkEnabled: Bool = false,
        steamBuiltinOpenGL: Bool = false
    ) {
        self.backend = backend
        self.dxvkAsync = dxvkAsync
        self.dxvkHud = dxvkHud
        self.glZinkEnabled = glZinkEnabled
        self.steamBuiltinOpenGL = steamBuiltinOpenGL
    }

    private enum CodingKeys: String, CodingKey {
        case backend
        case dxvkAsync
        case dxvkHud
        case glZinkEnabled
        case steamBuiltinOpenGL
        case dxvk
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let rawBackend = try container.decodeIfPresent(String.self, forKey: .backend) {
            backend = TranslationBackend(rawValue: rawBackend) ?? .dxvk
        } else if let legacyDXVKToggle = try container.decodeIfPresent(Bool.self, forKey: .dxvk) {
            backend = legacyDXVKToggle ? .dxvk : .none
        } else {
            backend = .dxvk
        }

        dxvkAsync = try container.decodeIfPresent(Bool.self, forKey: .dxvkAsync) ?? true
        dxvkHud = try container.decodeIfPresent(DXVKHUD.self, forKey: .dxvkHud) ?? .off
        glZinkEnabled = try container.decodeIfPresent(Bool.self, forKey: .glZinkEnabled) ?? false
        steamBuiltinOpenGL = try container.decodeIfPresent(Bool.self, forKey: .steamBuiltinOpenGL) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backend.rawValue, forKey: .backend)
        try container.encode(dxvkAsync, forKey: .dxvkAsync)
        try container.encode(dxvkHud, forKey: .dxvkHud)
        try container.encode(glZinkEnabled, forKey: .glZinkEnabled)
        try container.encode(steamBuiltinOpenGL, forKey: .steamBuiltinOpenGL)
    }
}

public struct BottleGPUConfig: Codable, Equatable, Sendable {
    public var spoofPreset: GPUSpoofPreset
    public var customVendorId: UInt16
    public var customDeviceId: UInt16
    public var customDescription: String
    public var customVRAM: UInt32
    public var deviceIdSalt: UInt8

    public init(
        spoofPreset: GPUSpoofPreset = .amdRX7900XTX,
        customVendorId: UInt16 = 0x1002,
        customDeviceId: UInt16 = 0x744c,
        customDescription: String = "AMD Radeon RX 7900 XTX",
        customVRAM: UInt32 = 24576,
        deviceIdSalt: UInt8 = 0
    ) {
        self.spoofPreset = spoofPreset
        self.customVendorId = customVendorId
        self.customDeviceId = customDeviceId
        self.customDescription = customDescription
        self.customVRAM = customVRAM
        self.deviceIdSalt = deviceIdSalt
    }

    private enum CodingKeys: String, CodingKey {
        case spoofPreset
        case customVendorId
        case customDeviceId
        case customDescription
        case customVRAM
        case deviceIdSalt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spoofPreset = try container.decodeIfPresent(GPUSpoofPreset.self, forKey: .spoofPreset) ?? .amdRX7900XTX
        customVendorId = try container.decodeIfPresent(UInt16.self, forKey: .customVendorId) ?? 0x1002
        customDeviceId = try container.decodeIfPresent(UInt16.self, forKey: .customDeviceId) ?? 0x744c
        customDescription = try container.decodeIfPresent(String.self, forKey: .customDescription) ?? "AMD Radeon RX 7900 XTX"
        customVRAM = try container.decodeIfPresent(UInt32.self, forKey: .customVRAM) ?? 24576
        deviceIdSalt = try container.decodeIfPresent(UInt8.self, forKey: .deviceIdSalt) ?? 0
    }

    public func resolvedIdentity() -> ResolvedGPUIdentity? {
        switch spoofPreset {
        case .off:
            nil
        case .custom:
            ResolvedGPUIdentity(
                vendorId: customVendorId,
                deviceId: customDeviceId ^ UInt16(deviceIdSalt),
                description: customDescription,
                vramMB: customVRAM
            )
        case .amdRX7900XTX:
            ResolvedGPUIdentity(vendorId: 0x1002, deviceId: 0x744c ^ UInt16(deviceIdSalt), description: "AMD Radeon RX 7900 XTX", vramMB: 24576)
        case .amdRX6800XT:
            ResolvedGPUIdentity(vendorId: 0x1002, deviceId: 0x73bf ^ UInt16(deviceIdSalt), description: "AMD Radeon RX 6800 XT", vramMB: 16384)
        case .nvidiaRTX4090:
            ResolvedGPUIdentity(vendorId: 0x10de, deviceId: 0x2684 ^ UInt16(deviceIdSalt), description: "NVIDIA GeForce RTX 4090", vramMB: 24576)
        case .nvidiaRTX3080:
            ResolvedGPUIdentity(vendorId: 0x10de, deviceId: 0x2206 ^ UInt16(deviceIdSalt), description: "NVIDIA GeForce RTX 3080", vramMB: 10240)
        }
    }
}

public struct BottleSettings: Codable, Equatable, Sendable {
    public static let metadataFileName = "Metadata.plist"
    public static let currentFileVersion = AppVersion(1, 0, 0)

    public var fileVersion: AppVersion
    public var info: BottleInfo
    public var wine: BottleWineConfig
    public var metal: BottleMetalConfig
    public var backend: BottleBackendConfig
    public var gpu: BottleGPUConfig

    public init(
        fileVersion: AppVersion = BottleSettings.currentFileVersion,
        info: BottleInfo = BottleInfo(),
        wine: BottleWineConfig = BottleWineConfig(),
        metal: BottleMetalConfig = BottleMetalConfig(),
        backend: BottleBackendConfig = BottleBackendConfig(),
        gpu: BottleGPUConfig = BottleGPUConfig()
    ) {
        self.fileVersion = fileVersion
        self.info = info
        self.wine = wine
        self.metal = metal
        self.backend = backend
        self.gpu = gpu
    }

    private enum CodingKeys: String, CodingKey {
        case fileVersion
        case info
        case wine
        case wineConfig
        case metal
        case metalConfig
        case backend
        case backendConfig
        case dxvkConfig
        case gpu
        case gpuConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fileVersion = try container.decodeIfPresent(AppVersion.self, forKey: .fileVersion)
            ?? BottleSettings.currentFileVersion
        info = try container.decodeIfPresent(BottleInfo.self, forKey: .info) ?? BottleInfo()

        if let wine = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wine) {
            self.wine = wine
        } else {
            self.wine = try container.decodeIfPresent(BottleWineConfig.self, forKey: .wineConfig)
                ?? BottleWineConfig()
        }

        if let metal = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metal) {
            self.metal = metal
        } else {
            self.metal = try container.decodeIfPresent(BottleMetalConfig.self, forKey: .metalConfig)
                ?? BottleMetalConfig()
        }

        if let backend = try container.decodeIfPresent(BottleBackendConfig.self, forKey: .backend) {
            self.backend = backend
        } else if let backend = try container.decodeIfPresent(BottleBackendConfig.self, forKey: .backendConfig) {
            self.backend = backend
        } else if let backend = try container.decodeIfPresent(BottleBackendConfig.self, forKey: .dxvkConfig) {
            self.backend = backend
        } else {
            self.backend = BottleBackendConfig()
        }

        if let gpu = try container.decodeIfPresent(BottleGPUConfig.self, forKey: .gpu) {
            self.gpu = gpu
        } else {
            self.gpu = try container.decodeIfPresent(BottleGPUConfig.self, forKey: .gpuConfig)
                ?? BottleGPUConfig()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileVersion, forKey: .fileVersion)
        try container.encode(info, forKey: .info)
        try container.encode(wine, forKey: .wineConfig)
        try container.encode(metal, forKey: .metalConfig)
        try container.encode(backend, forKey: .backendConfig)
        try container.encode(gpu, forKey: .gpuConfig)
    }

    public func resolvedGPUIdentity() -> ResolvedGPUIdentity? {
        gpu.resolvedIdentity()
    }
}
