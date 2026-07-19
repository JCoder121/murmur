// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chirp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ChirpCore"),
        .executableTarget(name: "Chirp", dependencies: ["ChirpCore"]),
        .testTarget(name: "ChirpCoreTests", dependencies: ["ChirpCore"]),
    ]
)
