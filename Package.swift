// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "IrisEditor",
    platforms: [
        .macOS(.v27)
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
