// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExpensiveLayerDemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ExpensiveLayerDemo",
            path: "Sources/ExpensiveLayerDemo"
        )
    ]
)
