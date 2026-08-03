// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchIsland", targets: ["NotchIsland"])
    ],
    targets: [
        .executableTarget(
            name: "NotchIsland",
            path: "Sources/NotchIsland"
        ),
        .testTarget(
            name: "NotchIslandTests",
            dependencies: ["NotchIsland"],
            path: "Tests/NotchIslandTests"
        )
    ]
)
