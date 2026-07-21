// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dictator",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.8.0"..<"0.9.0")
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10068/llama-b10068-xcframework.zip",
            checksum: "5238397dd4ca305c9db537c3ae106948909ba2605e77d2d3463ac2d2ca08cc8a"
        ),
        .target(
            name: "DictatorLLM",
            dependencies: ["llama"],
            path: "Sources/DictatorLLM"
        ),
        .executableTarget(
            name: "Dictator",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "DictatorLLM",
            ],
            path: "Sources/Dictator"
        ),
        .executableTarget(
            name: "DictatorCLI",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "DictatorLLM",
            ],
            path: "Sources/DictatorCLI"
        )
    ]
)
