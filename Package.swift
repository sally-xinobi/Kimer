// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kimer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Kimer",
            path: "Sources/Kimer"
        )
    ]
)
