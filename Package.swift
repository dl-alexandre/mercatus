// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArbitrageEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ArbitrageEngine",
            targets: ["ArbitrageEngine"]
        ),
        .library(
            name: "MLPatternEngine",
            targets: ["MLPatternEngine"]
        ),
        .library(
            name: "MLPatternEngineAPI",
            targets: ["MLPatternEngineAPI"]
        ),
        .library(
            name: "MLPatternEngineIntegration",
            targets: ["MLPatternEngineIntegration"]
        ),
        .library(
            name: "MLPatternEngineSummarization",
            targets: ["MLPatternEngineSummarization"]
        ),
        .library(
            name: "SmartVestor",
            targets: ["SmartVestor"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", branch: "main")
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
        .target(
            name: "SmartVestor",
            dependencies: [
                "Core",
                "Utils",
                "MLPatternEngine"
            ],
            path: "Sources/SmartVestorCore"
        ),
        .executableTarget(
            name: "SmartVestorCLI",
            dependencies: [
                "SmartVestor",
                "MLPatternEngine",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SmartVestor",
            sources: ["WorkingCLI.swift"]
        ),
        .target(
            name: "MLPatternEngine",
            dependencies: [
                "Core",
                "Utils"
            ],
            path: "Sources/MLPatternEngine",
            exclude: ["API", "Integration", "MLXModels", "Summarization"],
            resources: [
                .process("README.md")
            ]
        ),
        .target(
            name: "MLPatternEngineMLX",
            dependencies: [
                "MLPatternEngine",
                "Core",
                "Utils",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift")
            ],
            path: "Sources/MLPatternEngine/MLXModels",
            exclude: ["README.md"]
        ),
        .target(
            name: "MLPatternEngineAPI",
            dependencies: [
                "MLPatternEngine",
                "Core",
                "Utils"
            ],
            path: "Sources/MLPatternEngine/API"
        ),
        .target(
            name: "MLPatternEngineIntegration",
            dependencies: [
                "MLPatternEngine",
                "Core",
                "Utils"
            ],
            path: "Sources/MLPatternEngine/Integration"
        ),
        .target(
            name: "MLPatternEngineSummarization",
            dependencies: [
                "MLPatternEngine",
                "Core",
                "Utils"
            ],
            path: "Sources/MLPatternEngine/Summarization",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "ArbitrageEngineTests",
            dependencies: [
                "Core",
                "Connectors",
                "SmartVestor",
                "Utils"
            ],
            path: "Tests/ArbitrageEngineTests"
        ),
        .testTarget(
            name: "MLPatternEngineTests",
            dependencies: [
                "MLPatternEngine",
                "MLPatternEngineMLX",
                "MLPatternEngineAPI",
                "MLPatternEngineSummarization",
                "Core",
                "Utils"
            ],
            path: "Tests/MLPatternEngineTests"
        ),
    ]
)
