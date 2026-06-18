// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LLM",
    // Foundation Models requires iOS/macOS 26+. OS 27-only symbols are gated at use sites.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(
            name: "LLM",
            targets: ["LLM"]
        ),
    ],
    dependencies: [
        // AnyLanguageModel for Foundation Models + Anthropic (no MLX trait needed)
        .package(
            path: "../AnyLanguageModel"
        ),
        // MLX directly from mlx-swift-lm
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            from: "2.30.0"
        )
    ],
    targets: [
        .target(
            name: "LLM",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                // The iPhoneSimulator SDK does not export every Metal symbol
                // used by mlx-swift. Keep MLX linked only into macOS builds.
                .product(name: "MLXLLM", package: "mlx-swift-lm", condition: .when(platforms: [.macOS])),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "LLMTests",
            dependencies: ["LLM"]
        ),
    ]
)
