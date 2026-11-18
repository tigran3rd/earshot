// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Earshot",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Earshot",
            path: "Sources/Earshot",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
