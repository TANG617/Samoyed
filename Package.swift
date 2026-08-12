// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SamoyedCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SamoyedCore",
            targets: ["SamoyedCore"]
        )
    ],
    targets: [
        .target(
            name: "SamoyedCore",
            path: "Samoyed/CoreShared"
        ),
        .testTarget(
            name: "SamoyedCoreTests",
            dependencies: ["SamoyedCore"],
            path: "Tests/SamoyedCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
