// swift-tools-version: 6.2

import Foundation
import PackageDescription

var targets: [Target] = [
    .executableTarget(
        name: "Notchy",
        path: "Sources/Notchy",
        // Face Check's Core ML model and its licence note. script/build_and_run.sh
        // compiles the model into the app's Resources; SwiftPM leaves the folder alone.
        exclude: ["Features/FaceCheck/Model"]
    )
]

// The test suite stays on the developer's Mac and is not in the repository, so its target
// is declared only where its folder exists. A fresh clone builds the app without it.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/NotchyTests") {
    targets.append(
        .testTarget(
            name: "NotchyTests",
            dependencies: ["Notchy"],
            path: "Tests/NotchyTests",
            resources: [.copy("Fixtures")]
        )
    )
}

let package = Package(
    name: "Notchy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Notchy", targets: ["Notchy"])
    ],
    targets: targets
)
