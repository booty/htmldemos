// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NebulaForge",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NebulaForgeCore", targets: ["NebulaForgeCore"]),
        .executable(name: "NebulaForge", targets: ["NebulaForgeApp"]),
    ],
    targets: [
        .target(name: "NebulaForgeCore"),
        .executableTarget(
            name: "NebulaForgeApp",
            dependencies: ["NebulaForgeCore"],
            resources: [.copy("Shaders")]
        ),
        .testTarget(name: "NebulaForgeCoreTests", dependencies: ["NebulaForgeCore"]),
        .testTarget(name: "NebulaForgeAppTests", dependencies: ["NebulaForgeApp"]),
    ]
)
