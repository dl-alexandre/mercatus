// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArbitrageEngine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ArbitrageEngine",
            targets: ["ArbitrageEngine"]
        ),
    ],
    targets: [
        .target(
            name: "Utils",
            path: "Sources/Utils"
        ),
        .target(
            name: "Core",
            dependencies: [
                "Utils"
            ],
            path: "Sources/Core"
        ),
        .target(
            name: "Connectors",
            dependencies: [
                "Utils",
                "Core"
            ],
            path: "Sources/Connectors"
        ),
        .executableTarget(
            name: "ArbitrageEngine",
            dependencies: [
                "Core",
                "Connectors"
            ],
            path: "Sources/ArbitrageEngineApp"
        ),
        .testTarget(
            name: "ArbitrageEngineTests",
            dependencies: [
                "Core",
                "Connectors",
                "Utils"
            ],
            path: "Tests/ArbitrageEngineTests"
        ),
    ]
)
