// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ccc",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ccc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "cccTests",
            dependencies: ["ccc"],
            path: "Tests"
        ),
    ]
)
