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
        .executableTarget(
            name: "MetalDuck",
            resources: [
                .process("Assets"),
                .process("Rendering/Shaders")
            ]
        )
    ]
)
