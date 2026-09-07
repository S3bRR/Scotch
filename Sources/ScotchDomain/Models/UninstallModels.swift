import Foundation

public struct UninstallTarget: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case runtime
        case settings
        case logs
        case cache
        case bottle
        case cli
        case temporary
        case appBundle
        case preferences
        case leftover
    }

    public var path: String
    public var kind: Kind
    public var exists: Bool
    public var byteCount: Int64

    public var id: String { path }

    public init(path: String, kind: Kind, exists: Bool, byteCount: Int64) {
        self.path = path
        self.kind = kind
        self.exists = exists
        self.byteCount = byteCount
    }
}

public struct UninstallPlan: Equatable, Sendable {
    public var targets: [UninstallTarget]
    public var includeBottles: Bool
    public var includeAppBundle: Bool

    public var existingTargets: [UninstallTarget] {
        targets.filter(\.exists)
    }

    public var totalByteCount: Int64 {
        existingTargets.reduce(0) { $0 + $1.byteCount }
    }

    public init(targets: [UninstallTarget], includeBottles: Bool, includeAppBundle: Bool) {
        self.targets = targets
        self.includeBottles = includeBottles
        self.includeAppBundle = includeAppBundle
    }
}

public struct UninstallResult: Equatable, Sendable {
    public var removedPaths: [String]
    public var skippedPaths: [String]
    public var errors: [String]
    public var scheduledAppBundleRemoval: Bool

    public init(
        removedPaths: [String] = [],
        skippedPaths: [String] = [],
        errors: [String] = [],
        scheduledAppBundleRemoval: Bool = false
    ) {
        self.removedPaths = removedPaths
        self.skippedPaths = skippedPaths
        self.errors = errors
        self.scheduledAppBundleRemoval = scheduledAppBundleRemoval
    }
}
