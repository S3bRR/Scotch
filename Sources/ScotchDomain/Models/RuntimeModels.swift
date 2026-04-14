import Foundation

public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let versionTag: String
    public let downloadURL: URL
    public let size: Int64
    public let sha256: String?

    public init(name: String, versionTag: String, downloadURL: URL, size: Int64, sha256: String? = nil) {
        self.name = name
        self.versionTag = versionTag
        self.downloadURL = downloadURL
        self.size = size
        self.sha256 = sha256
    }
}

public struct RuntimeReleases: Equatable, Sendable {
    public let wine: ReleaseAsset
    public let dxvk: ReleaseAsset
    public let dxmt: ReleaseAsset

    public init(wine: ReleaseAsset, dxvk: ReleaseAsset, dxmt: ReleaseAsset) {
        self.wine = wine
        self.dxvk = dxvk
        self.dxmt = dxmt
    }
}

public struct DownloadedRuntimeArchives: Equatable, Sendable {
    public let runtimeReleases: RuntimeReleases
    public let wineArchive: URL
    public let dxvkArchive: URL
    public let dxmtArchive: URL

    public init(runtimeReleases: RuntimeReleases, wineArchive: URL, dxvkArchive: URL, dxmtArchive: URL) {
        self.runtimeReleases = runtimeReleases
        self.wineArchive = wineArchive
        self.dxvkArchive = dxvkArchive
        self.dxmtArchive = dxmtArchive
    }
}

public enum OverlayComponent: String, Codable, CaseIterable, Sendable {
    case winemacOpenGLPatch
    case d3dmetal
    case zink

    public var displayName: String {
        switch self {
        case .winemacOpenGLPatch:
            "winemac OpenGL patch"
        case .d3dmetal:
            "D3DMetal"
        case .zink:
            "Zink"
        }
    }
}

public struct OverlayInstallResult: Equatable, Sendable {
    public let component: OverlayComponent
    public let installedVersion: String?
    public let errorMessage: String?

    public var succeeded: Bool {
        installedVersion != nil && errorMessage == nil
    }

    public init(component: OverlayComponent, installedVersion: String?, errorMessage: String?) {
        self.component = component
        self.installedVersion = installedVersion
        self.errorMessage = errorMessage
    }
}

public struct RuntimeManifest: Codable, Equatable, Sendable {
    public static let fileName = "ScotchRuntimeManifest.plist"

    public var schemaVersion: Int
    public var wineVersion: String
    public var dxvkVersion: String
    public var dxmtVersion: String
    public var d3dmetalVersion: String?
    public var winemacPatchVersion: String?
    public var zinkVersion: String?

    public init(
        schemaVersion: Int = 1,
        wineVersion: String,
        dxvkVersion: String,
        dxmtVersion: String,
        d3dmetalVersion: String? = nil,
        winemacPatchVersion: String? = nil,
        zinkVersion: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.wineVersion = wineVersion
        self.dxvkVersion = dxvkVersion
        self.dxmtVersion = dxmtVersion
        self.d3dmetalVersion = d3dmetalVersion
        self.winemacPatchVersion = winemacPatchVersion
        self.zinkVersion = zinkVersion
    }
}

public struct OverlayDrift: Equatable, Sendable {
    public let component: OverlayComponent
    public let installedVersion: String?
    public let expectedVersion: String

    public init(component: OverlayComponent, installedVersion: String?, expectedVersion: String) {
        self.component = component
        self.installedVersion = installedVersion
        self.expectedVersion = expectedVersion
    }
}
