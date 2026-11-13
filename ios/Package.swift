// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GanfanHandbook",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GanfanCore", targets: ["GanfanCore"])
    ],
    targets: [
        .target(name: "GanfanCore"),
        .testTarget(name: "GanfanCoreTests", dependencies: ["GanfanCore"])
    ]
)
