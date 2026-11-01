// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeBuddy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
