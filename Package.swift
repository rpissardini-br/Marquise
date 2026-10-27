// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Marquise",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Marquise",
            path: "Sources/Marquise",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
