// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "IrisEditor",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "IrisEditor",
            path: "Sources/IrisEditor"
        ),
        .testTarget(
            name: "IrisEditorTests",
            dependencies: ["IrisEditor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
