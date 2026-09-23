// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "spawn",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/containerization.git", exact: "0.45.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "spawn",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationArchive", package: "containerization"),
                .product(name: "ContainerizationEXT4", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "spawnTests",
            dependencies: [
                "spawn",
                .product(name: "Containerization", package: "containerization"),
            ],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
