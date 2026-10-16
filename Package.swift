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
            path: "Sources/Notchy",
            // Face Check's Core ML model and its licence note. script/build_and_run.sh
            // compiles the model into the app's Resources; SwiftPM leaves the folder alone.
            exclude: ["Features/FaceCheck/Model"]
        ),
        .testTarget(
            name: "NotchyTests",
            dependencies: ["Notchy"],
            path: "Tests/NotchyTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
