// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shuntbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Shuntbar"),
        .testTarget(name: "ShuntbarTests", dependencies: ["Shuntbar"]),
    ]
)
