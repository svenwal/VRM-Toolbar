// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VRMToolbar",
    platforms: [.macOS(.v14)],
    targets: [
        // Snapshot model shared by the app and the Notification Center widgets.
        .target(
            name: "VRMShared",
            path: "Sources/VRMShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "VRMToolbar",
            dependencies: ["VRMShared"],
            path: "Sources/VRMToolbar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // WidgetKit extension; scripts/bundle.sh wraps the binary into VRMWidget.appex.
        .executableTarget(
            name: "VRMWidget",
            dependencies: ["VRMShared"],
            path: "Sources/VRMWidget",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]
        ),
        .testTarget(
            name: "VRMToolbarTests",
            dependencies: ["VRMToolbar"],
            path: "Tests/VRMToolbarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
