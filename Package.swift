// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThingsSync",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ThingsSync",
            path: "ThingsSync"
        ),
    ]
)
