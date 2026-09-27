// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoInputSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AutoInputSwitcherCore",
            targets: ["AutoInputSwitcherCore"]
        ),
        // App code lives in a library so the test target can exercise it without
        // competing with the executable main entry point.
        .library(
            name: "AutoInputSwitcherApp",
            targets: ["AutoInputSwitcherApp"]
        ),
        .executable(
            name: "AutoInputSwitcher",
            targets: ["AutoInputSwitcher"]
        ),
        .executable(
            name: "AutoInputSwitcherCoreChecks",
            targets: ["AutoInputSwitcherCoreChecks"]
        )
    ],
    dependencies: [
        // Pinned exactly: an updater must not change its update logic by accident.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        // Core stays free of AppKit and Sparkle so it can be tested anywhere.
        .target(
            name: "AutoInputSwitcherCore"
        ),
        .target(
            name: "AutoInputSwitcherApp",
            dependencies: [
                "AutoInputSwitcherCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "AutoInputSwitcher",
            dependencies: ["AutoInputSwitcherApp"]
        ),
        .executableTarget(
            name: "AutoInputSwitcherCoreChecks",
            dependencies: ["AutoInputSwitcherCore"]
        ),
        .testTarget(
            name: "AutoInputSwitcherCoreTests",
            dependencies: ["AutoInputSwitcherCore"]
        ),
        .testTarget(
            name: "AutoInputSwitcherTests",
            dependencies: ["AutoInputSwitcherApp"]
        )
    ]
)
