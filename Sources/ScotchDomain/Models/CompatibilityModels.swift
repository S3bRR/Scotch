import Foundation

public enum TranslationBackend: String, Codable, CaseIterable, Sendable {
    case dxvk
    case dxmt
    case d3dmetal
    case zink
    case none

    public var displayName: String {
        switch self {
        case .dxvk:
            "DXVK (DX10/11)"
        case .dxmt:
            "DXMT (DX10/11)"
        case .d3dmetal:
            "D3DMetal (DX11/12)"
        case .zink:
            "Zink (OpenGL 4.6)"
        case .none:
            "None"
        }
    }

    public var wineDLLOverrides: String? {
        switch self {
        case .dxvk:
            "d3d10core,d3d11=n,b"
        case .dxmt:
            "dxgi,d3d10core,d3d11,winemetal=n,b"
        case .d3dmetal:
            "dxgi,d3d11,d3d12=n,b"
        case .zink:
            "opengl32,libgallium_wgl,libglapi=n,b"
        case .none:
            nil
        }
    }
}

public enum EnhancedSyncMode: String, Codable, CaseIterable, Sendable {
    case none
    case esync
    case msync

    private enum LegacyCodingKeys: String, CodingKey {
        case none
        case esync
        case msync
    }

    public init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self),
           let value = EnhancedSyncMode(rawValue: raw) {
            self = value
            return
        }

        let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if container.contains(.none) {
            self = .none
            return
        }
        if container.contains(.esync) {
            self = .esync
            return
        }
        if container.contains(.msync) {
            self = .msync
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .none,
            in: container,
            debugDescription: "Unsupported EnhancedSyncMode payload"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum DXVKHUD: String, Codable, CaseIterable, Sendable {
    case full
    case partial
    case fps
    case off

    private enum LegacyCodingKeys: String, CodingKey {
        case full
        case partial
        case fps
        case off
    }

    public init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self),
           let value = DXVKHUD(rawValue: raw) {
            self = value
            return
        }

        let container = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if container.contains(.full) {
            self = .full
            return
        }
        if container.contains(.partial) {
            self = .partial
            return
        }
        if container.contains(.fps) {
            self = .fps
            return
        }
        if container.contains(.off) {
            self = .off
            return
        }

        throw DecodingError.dataCorruptedError(
            forKey: .off,
            in: container,
            debugDescription: "Unsupported DXVKHUD payload"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum WindowsVersion: String, Codable, CaseIterable, Sendable {
    case winXP = "winxp64"
    case win7
    case win8
    case win81
    case win10
    case win11

    public var displayName: String {
        switch self {
        case .winXP:
            "Windows XP"
        case .win7:
            "Windows 7"
        case .win8:
            "Windows 8"
        case .win81:
            "Windows 8.1"
        case .win10:
            "Windows 10"
        case .win11:
            "Windows 11"
        }
    }
}

public enum GPUSpoofPreset: String, Codable, CaseIterable, Sendable {
    case amdRX7900XTX
    case amdRX6800XT
    case nvidiaRTX4090
    case nvidiaRTX3080
    case custom
    case off

    public var displayName: String {
        switch self {
        case .amdRX7900XTX:
            "AMD Radeon RX 7900 XTX"
        case .amdRX6800XT:
            "AMD Radeon RX 6800 XT"
        case .nvidiaRTX4090:
            "NVIDIA GeForce RTX 4090"
        case .nvidiaRTX3080:
            "NVIDIA GeForce RTX 3080"
        case .custom:
            "Custom"
        case .off:
            "Off"
        }
    }
}

public struct ResolvedGPUIdentity: Codable, Equatable, Sendable {
    public let vendorId: UInt16
    public let deviceId: UInt16
    public let description: String
    public let vramMB: UInt32

    public init(vendorId: UInt16, deviceId: UInt16, description: String, vramMB: UInt32) {
        self.vendorId = vendorId
        self.deviceId = deviceId
        self.description = description
        self.vramMB = vramMB
    }
}
