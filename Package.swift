// swift-tools-version:5.9
import Foundation
import PackageDescription

// Optional components, both OFF by default so a plain `swift build` produces a
// binary with no inference engine and no code that can reach a network:
//   DICTATOR_LLM=1      embeds llama.cpp and enables the AI polish stage
//   DICTATOR_DOWNLOAD=1 allows fetching speech models from Hugging Face
// See `make app` (clean) vs `make app-full` (both enabled).
let environment = ProcessInfo.processInfo.environment
let enableLLM = environment["DICTATOR_LLM"] == "1"
let enableDownload = environment["DICTATOR_DOWNLOAD"] == "1"

var swiftSettings: [SwiftSetting] = []
if enableLLM { swiftSettings.append(.define("DICTATOR_LLM")) }
if enableDownload { swiftSettings.append(.define("DICTATOR_DOWNLOAD")) }

var sharedDependencies: [Target.Dependency] = [
    .product(name: "FluidAudio", package: "FluidAudio")
]
var targets: [Target] = []

if enableLLM {
    targets.append(
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10068/llama-b10068-xcframework.zip",
            checksum: "5238397dd4ca305c9db537c3ae106948909ba2605e77d2d3463ac2d2ca08cc8a"
        )
    )
    targets.append(
        .target(
            name: "DictatorLLM",
            dependencies: ["llama"],
            path: "Sources/DictatorLLM"
        )
    )
    sharedDependencies.append("DictatorLLM")
}

targets.append(
    .executableTarget(
        name: "Dictator",
        dependencies: sharedDependencies,
        path: "Sources/Dictator",
        swiftSettings: swiftSettings
    )
)
targets.append(
    .executableTarget(
        name: "DictatorCLI",
        dependencies: sharedDependencies,
        path: "Sources/DictatorCLI",
        swiftSettings: swiftSettings
    )
)

let package = Package(
    name: "Dictator",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.8.0"..<"0.9.0")
    ],
    targets: targets
)
