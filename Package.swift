// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarkdownView",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MarkdownView",
            path: "Sources/MarkdownView"
        ),
        .testTarget(
            name: "MarkdownViewTests",
            dependencies: ["MarkdownView"],
            path: "Tests/MarkdownViewTests"
        ),
    ]
)
