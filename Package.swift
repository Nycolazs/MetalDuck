// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MetalDuck",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MetalDuck", targets: ["MetalDuck"])
    ],
    targets: [
        // Everything except the entry point, so it can be tested.
        .target(
            name: "MetalDuckKit",
            path: "Sources/MetalDuck",
            resources: [
                .process("Assets"),
                // Copied as text: the app compiles Present.metal itself at launch. Processing
                // it would precompile it instead, which needs the Metal Toolchain to build
                // and leaves no source in the bundle to load.
                .copy("Rendering/Shaders")
            ]
        ),
        .executableTarget(
            name: "MetalDuck",
            dependencies: ["MetalDuckKit"],
            path: "Sources/MetalDuckApp"
        ),
        .testTarget(
            name: "MetalDuckKitTests",
            dependencies: ["MetalDuckKit"]
        )
    ]
)
