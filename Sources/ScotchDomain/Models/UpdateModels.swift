import Foundation

public enum RuntimeComponent: String, Codable, CaseIterable, Sendable {
    case wine, dxvk, dxmt, zink, d3dmetal
}
public struct RuntimePackage: Codable, Equatable, Sendable {
    public var component: RuntimeComponent
    public var layoutVersion: Int?
    public var version: String
    public var url: URL
    public var fileName: String
    public var size: Int64
    public var sha256: String
    public var asset: ReleaseAsset { ReleaseAsset(name: fileName, versionTag: version, downloadURL: url, size: size, sha256: sha256) }
}
public struct ApprovedRuntimeSet: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var minimumAppBuild: Int
    public var minimumMacOS: Int
    public var architecture: String
    public var packages: [RuntimePackage]
    public func package(_ component: RuntimeComponent) -> RuntimePackage? { packages.first { $0.component == component } }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && !value.hasPrefix(".") && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }
    }
}
public struct RuntimeUpdateFeed: Codable, Sendable {
    public var schemaVersion: Int
    public var revision: Int
    public var validUntil: Date
    public var sets: [ApprovedRuntimeSet]
}
public struct SignedUpdateEnvelope: Codable, Sendable {
    public var payload: String
    public var signature: String
    public init(payload: String, signature: String) { self.payload = payload; self.signature = signature }
}
public struct RuntimeSelection: Codable, Sendable {
    public var defaultSetID: String?
    public init(defaultSetID: String? = nil) { self.defaultSetID = defaultSetID }
}
public enum RuntimeCheckResult: Sendable, Equatable {
    case current
    case available(ApprovedRuntimeSet)
    case repair(ApprovedRuntimeSet)
    case incompatible(String)
}
public enum UpdateConfiguration {
    public static let runtimeFeedURL = URL(string: "https://s3brr.github.io/Scotch/updates/runtime.json")!
    public static let runtimePublicKey = "FFBpTlRRFiys/bDo7bALz3nVy8NHchA0IVOEn/DvQ+8="
}
