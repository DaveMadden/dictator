// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dictator",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", "0.8.0"..<"0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Dictator",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Dictator"
        ),
        .executableTarget(
            name: "DictatorCLI",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/DictatorCLI"
        )
    ]
)
