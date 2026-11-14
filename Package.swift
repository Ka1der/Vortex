// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VortexShared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VortexShared",
            targets: ["VortexShared"]
        ),
        .library(
            name: "Libbox",
            targets: ["Libbox"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "Libbox",
            path: "Frameworks/Libbox.xcframework"
        ),
        .target(
            name: "VortexShared",
            dependencies: [],
            path: "Vortex/Shared"
        )
    ]
)
