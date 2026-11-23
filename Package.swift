// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenBoard",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ScreenBoard",
            path: "Sources/ScreenBoard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
