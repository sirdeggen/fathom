// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fathom",
    products: [
        .library(name: "FathomCore", targets: ["FathomCore"]),
    ],
    targets: [
        .target(
            name: "FathomCore",
            resources: [.process("Resources/regions.json")]
        ),
        .testTarget(
            name: "FathomCoreTests",
            dependencies: ["FathomCore"]
        ),
    ]
)
