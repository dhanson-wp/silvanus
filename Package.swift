// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Silvanus",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet speech recognition on the Neural Engine. Pinned exactly:
        // FluidAudio has made source-breaking changes in patch releases.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.13.5"),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "SilvanusKit"),
        .executableTarget(
            name: "Silvanus",
            dependencies: ["SilvanusKit", .product(name: "FluidAudio", package: "FluidAudio")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SilvanusKitTests", dependencies: ["SilvanusKit"]),
    ]
)
