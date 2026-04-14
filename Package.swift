// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ScotchV2",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "ScotchDomain", targets: ["ScotchDomain"]),
        .library(name: "ScotchInfrastructure", targets: ["ScotchInfrastructure"]),
        .library(name: "ScotchRuntime", targets: ["ScotchRuntime"]),
        .library(name: "ScotchFeatures", targets: ["ScotchFeatures"]),
        .executable(name: "ScotchThumbnail", targets: ["ScotchThumbnail"]),
        .executable(name: "ScotchCmd", targets: ["ScotchCmd"]),
        .executable(name: "ScotchApp", targets: ["ScotchApp"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ScotchDomain",
            dependencies: []
        ),
        .target(
            name: "ScotchInfrastructure",
            dependencies: ["ScotchDomain"]
        ),
        .target(
            name: "ScotchRuntime",
            dependencies: ["ScotchDomain", "ScotchInfrastructure"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "ScotchFeatures",
            dependencies: ["ScotchDomain", "ScotchInfrastructure", "ScotchRuntime"]
        ),
        .executableTarget(
            name: "ScotchThumbnail",
            dependencies: ["ScotchRuntime"],
            exclude: [
                "Info.plist",
                "ScotchThumbnail.entitlements"
            ]
        ),
        .executableTarget(
            name: "ScotchCmd",
            dependencies: ["ScotchDomain", "ScotchInfrastructure", "ScotchRuntime"]
        ),
        .executableTarget(
            name: "ScotchApp",
            dependencies: ["ScotchFeatures"],
            exclude: [
                "Info.plist",
                "Scotch.entitlements",
                "Assets.xcassets"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ScotchApp/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "ScotchDomainTests",
            dependencies: ["ScotchDomain"]
        ),
        .testTarget(
            name: "ScotchRuntimeTests",
            dependencies: ["ScotchRuntime", "ScotchDomain", "ScotchInfrastructure"]
        ),
        .testTarget(
            name: "ScotchFeaturesTests",
            dependencies: ["ScotchFeatures", "ScotchDomain", "ScotchInfrastructure", "ScotchRuntime"]
        )
    ],
    swiftLanguageModes: [.v6]
)
