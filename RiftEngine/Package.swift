// swift-tools-version: 6.0
// standalone package: `swift test` must work here without the app project (sdd §5.1)
import PackageDescription

let package = Package(
    name: "RiftEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "RiftEngine", targets: ["RiftEngine"])
    ],
    targets: [
        .target(name: "RiftEngine"),
        .testTarget(
            name: "RiftEngineTests",
            dependencies: ["RiftEngine"],
            resources: [.copy("Corpus")]
        )
    ]
)
