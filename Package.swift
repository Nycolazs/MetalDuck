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
    dependencies: [
        // Translates the SPIR-V shaders in the user's Lossless.dll to Metal, in the app (Lossless FG engine).
        // Tag vulkan-sdk-1.4.363.0.
        .package(url: "https://github.com/KhronosGroup/SPIRV-Cross.git", revision: "f11ba9f0b21ba8fc15153d50a2a1ae31ab1cf8f7"),
        // LSFG 3.1 pass graph on Metal (MIT). Pinned to the fork until the public LSFGKernels initializer
        // is merged upstream (MaximKotliar/lsfg-metal).
        .package(url: "https://github.com/kwanLeeFrmVi/lsfg-metal.git", revision: "ca7d9be15ee6e07025cb315ba77729870d6ca454")
    ],
    targets: [
        .executableTarget(
            name: "MetalDuck",
            dependencies: [
                "LosslessShaderTranslator",
                .product(name: "LSFGCore", package: "lsfg-metal")
            ],
            resources: [
                .process("Assets"),
                .process("Rendering/Shaders")
            ]
        ),
        .testTarget(
            name: "MetalDuckTests",
            dependencies: ["MetalDuck"]
        ),
        // C wrapper around SPIRV-Cross, so Swift never imports its C++ headers.
        .target(
            name: "LosslessShaderTranslator",
            dependencies: [
                .product(name: "SPIRV-Cross", package: "SPIRV-Cross")
            ]
        )
    ],
    cxxLanguageStandard: .cxx17
)
