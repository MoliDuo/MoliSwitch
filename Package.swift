// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoliSwitch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MoliSwitchCore",
            targets: ["MoliSwitchCore"]
        ),
        // App code lives in a library so the test target can exercise it without
        // competing with the executable main entry point.
        .library(
            name: "MoliSwitchApp",
            targets: ["MoliSwitchApp"]
        ),
        .executable(
            name: "MoliSwitch",
            targets: ["MoliSwitch"]
        ),
        .executable(
            name: "MoliSwitchCoreChecks",
            targets: ["MoliSwitchCoreChecks"]
        ),
    ],
    dependencies: [
        // Pinned exactly: an updater must not change its update logic by accident.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Core stays free of AppKit and Sparkle so it can be tested anywhere.
        .target(
            name: "MoliSwitchCore"
        ),
        .target(
            name: "MoliSwitchApp",
            dependencies: [
                "MoliSwitchCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("OSAKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "MoliSwitch",
            dependencies: ["MoliSwitchApp"]
        ),
        .executableTarget(
            name: "MoliSwitchCoreChecks",
            dependencies: ["MoliSwitchCore"]
        ),
        .testTarget(
            name: "MoliSwitchCoreTests",
            dependencies: ["MoliSwitchCore"]
        ),
        .testTarget(
            name: "MoliSwitchTests",
            dependencies: ["MoliSwitchApp"]
        ),
    ]
)
