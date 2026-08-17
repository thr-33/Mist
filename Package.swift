// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mist",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mist",
            path: "Sources/Mist"
        ),
        .testTarget(
            name: "MistTests",
            dependencies: ["Mist"],
            path: "Tests/MistTests"
        ),
    ]
)
