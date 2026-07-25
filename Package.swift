// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SevenMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SevenMac",
            path: "Sources/SevenMac"
        )
    ]
)
