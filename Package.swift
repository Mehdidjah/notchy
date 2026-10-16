// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Notchy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Notchy", targets: ["Notchy"])
    ],
    targets: [
        .executableTarget(
            name: "Notchy",
            path: "Sources/Notchy"
        ),
        .testTarget(
            name: "NotchyTests",
            dependencies: ["Notchy"],
            path: "Tests/NotchyTests"
        )
    ]
)
