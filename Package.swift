// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WisprClone",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WisprCloneCore"),
        .executableTarget(name: "WisprClone", dependencies: ["WisprCloneCore"]),
        .testTarget(name: "WisprCloneCoreTests", dependencies: ["WisprCloneCore"]),
    ]
)
