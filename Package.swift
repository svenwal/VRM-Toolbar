// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VRMToolbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VRMToolbar",
            path: "Sources/VRMToolbar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VRMToolbarTests",
            dependencies: ["VRMToolbar"],
            path: "Tests/VRMToolbarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
