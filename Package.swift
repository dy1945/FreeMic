// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FreeMic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FreeMic",
            path: "Sources/FreeMic"
        )
    ]
)
