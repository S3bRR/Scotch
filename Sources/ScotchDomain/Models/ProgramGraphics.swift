import Foundation

public enum ProgramGraphicsMode: String, Codable, CaseIterable, Sendable {
    case bottle, automatic, manual
    public var displayName: String {
        switch self { case .bottle: "Use Bottle Setting"; case .automatic: "Auto"; case .manual: "Choose Backend" }
    }
}

public struct ProgramGraphicsChoice: Codable, Equatable, Hashable, Sendable {
    public var backend: TranslationBackend
    public var zinkEnabled: Bool
    public var executableFingerprint: String
    public var runtimeFingerprint: String
    public var configurationFingerprint: String?
    public init(backend: TranslationBackend, zinkEnabled: Bool, executableFingerprint: String, runtimeFingerprint: String, configurationFingerprint: String? = nil) {
        self.backend = backend; self.zinkEnabled = zinkEnabled
        self.executableFingerprint = executableFingerprint; self.runtimeFingerprint = runtimeFingerprint
        self.configurationFingerprint = configurationFingerprint
    }
}

public enum WindowsArchitecture: String, Sendable {
    case x86 = "32-bit x86", x64 = "64-bit x86", unsupported = "Unsupported architecture", unknown = "Unknown architecture"
}
public enum GraphicsAPI: String, CaseIterable, Hashable, Sendable {
    case d3d9 = "DirectX 9", d3d10 = "DirectX 10", d3d11 = "DirectX 11", d3d12 = "DirectX 12", openGL = "OpenGL", vulkan = "Vulkan"
}
public struct ExecutableGraphicsAnalysis: Sendable {
    public var architecture: WindowsArchitecture
    public var apis: Set<GraphicsAPI>
    public var imports: [String]
    public var fingerprint: String
    public var limited: Bool
    public var explanation: String
    public init(architecture: WindowsArchitecture, apis: Set<GraphicsAPI>, imports: [String], fingerprint: String, limited: Bool, explanation: String) {
        self.architecture = architecture; self.apis = apis; self.imports = imports
        self.fingerprint = fingerprint; self.limited = limited; self.explanation = explanation
    }
}
public struct ProgramGraphicsRecommendation: Sendable {
    public var analysis: ExecutableGraphicsAnalysis
    public var backend: TranslationBackend?
    public var automatic: Bool
    public var reason: String
    public var availabilityIssue: String?
    public var remembered: Bool
    public var currentBackend: TranslationBackend
    public var usesAuto: Bool
    public init(analysis: ExecutableGraphicsAnalysis, backend: TranslationBackend?, automatic: Bool, reason: String, availabilityIssue: String?, remembered: Bool, currentBackend: TranslationBackend, usesAuto: Bool) {
        self.analysis = analysis; self.backend = backend; self.automatic = automatic
        self.reason = reason; self.availabilityIssue = availabilityIssue; self.remembered = remembered
        self.currentBackend = currentBackend
        self.usesAuto = usesAuto
    }
}
