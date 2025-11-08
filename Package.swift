// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArbitrageEngine",
    platforms: [
        .macOS(.v15)
    ],
    products: [

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
        .library(
            name: "ReinforcementLearning",
            targets: ["ReinforcementLearning"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0")
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
                "Core",
                "SmartVestor"
            ],
            path: "Sources/Connectors"
        ),
        .executableTarget(
        name: "ArbitrageEngine",
        dependencies: [
        "Core",
        "Connectors"
        ],
        path: "Sources/ArbitrageEngineApp",
            exclude: ["AGENTS.md"]
        ),
        .target(
        name: "SmartVestor",
        dependencies: [
        "Core",
        "Utils",
        "MLPatternEngine",
        "MLPatternEngineMLX",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio")
        ],
        path: "Sources/SmartVestorCore",
            exclude: ["AGENTS.md"]
        ),
        .target(
        name: "SmartVestorMLXAdapter",
        dependencies: [
        .product(name: "MLX", package: "mlx-swift")
        ],
        path: "Sources/SmartVestorMLXAdapter",
        exclude: ["AGENTS.md"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
        name: "SmartVestorCLI",
        dependencies: [
        "SmartVestor",
        "MLPatternEngine",
        "MLPatternEngineIntegration",
        "MLPatternEngineSummarization",
        "Connectors",
        "SmartVestorMLXAdapter",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio")
        ],
        path: "Sources/SmartVestor",
        exclude: ["AGENTS.md"],
            sources: ["WorkingCLI.swift", "StartCommand.swift", "StopCommand.swift", "HelpState.swift", "ExecuteCutoverCommand.swift", "ExportLedgerCommand.swift", "Commands/TUIBenchCommand.swift", "Commands/TUIGraphTestCommand.swift", "Commands/FeatureExtractionDiagnostic.swift", "Commands/TUIDataCommand.swift"]
        ),
        .executableTarget(
        name: "DataCleanupTool",
        dependencies: [
        "MLPatternEngine",
        "Utils"
        ],
        path: "Sources/DataCleanupTool",
            exclude: ["AGENTS.md"]
        ),
        .target(
        name: "MLPatternEngine",
        dependencies: [
        "Core",
        "Utils"
        ],
        path: "Sources/MLPatternEngine",
        exclude: ["API", "Integration", "MLXModels", "Summarization", "AGENTS.md"],
        resources: [
        .process("README.md")] ),
        .target(
            name: "MLPatternEngineMLX",
            dependencies: [
                "MLPatternEngine",
                "Core",
                "Utils",
                "SmartVestorMLXAdapter",
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
        .target(
        name: "ReinforcementLearning",
        dependencies: [
        "Core",
        "Utils",
        "MLPatternEngine",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXOptimizers", package: "mlx-swift")
        ],
        path: "Sources/ReinforcementLearning",
            exclude: ["AGENTS.md"]
        ),
        .testTarget(
            name: "SmartVestorTests",
            dependencies: [
                "SmartVestor",
                "Utils",
                "Core"
            ],
            path: "Tests/SmartVestorTests",
            resources: [
                .process("__snapshots__")
            ],
            swiftSettings: [
                .define("TESTING")
            ]
        )
    ]
)
