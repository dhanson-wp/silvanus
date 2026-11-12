// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Silvanus",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet speech recognition on the Neural Engine. Pinned exactly:
        // FluidAudio has made source-breaking changes in patch releases.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.5"),
        // In-app updates. Pinned to the version PressShot ships.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.0"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "SilvanusKit"),
        .executableTarget(
            name: "Silvanus",
            dependencies: ["SilvanusKit", .product(name: "FluidAudio", package: "FluidAudio"),
                           .product(name: "Sparkle", package: "Sparkle"), "llama"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // llama.cpp, prebuilt by its own project: runs the local model that writes
        // to-dos and summaries. build.sh copies the framework into the app.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12282/llama-b12282-xcframework.zip",
            checksum: "3789362d50cb70b057009bf7bfab2dbd52a5e552d8c0b9a84ca37009c4657fa0"
        ),
        .testTarget(name: "SilvanusKitTests", dependencies: ["SilvanusKit"]),
    ]
)
