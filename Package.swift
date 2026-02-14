// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "spawn",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
        .package(path: "../containerization"),
    ],
    targets: [
        .executableTarget(
            name: "spawn",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ContainerizationOCI", package: "containerization"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "spawnTests",
            dependencies: [
                "spawn",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
