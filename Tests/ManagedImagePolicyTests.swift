import Foundation
import Testing

@testable import spawn

@Test func managedImagePolicyUsesDetectionWhenNoOverridesArePresent() throws {
    let workspace = try makeTempDir(files: ["state.json": #"{"spawn-rust:latest": {}}"#])
    let resolution = try ManagedImagePolicy.resolve(
        detection: ToolchainDetector.Inspection(toolchain: .rust, source: .cargo),
        toolchainOverride: nil,
        imageOverride: nil,
        storeRoot: workspace
    )

    #expect(resolution.toolchain == .rust)
    #expect(resolution.image == "spawn-rust:latest")
    #expect(resolution.warnings.isEmpty)
}

@Test func managedImagePolicyRejectsMissingManagedImageWithBuildHint() throws {
    let storeRoot = try makeTempDir(files: ["state.json": "{}"])

    #expect(throws: SpawnError.self) {
        _ = try ManagedImagePolicy.resolve(
            detection: ToolchainDetector.Inspection(toolchain: .go, source: .goMod),
            toolchainOverride: nil,
            imageOverride: nil,
            storeRoot: storeRoot
        )
    }
}

@Test func managedImagePolicyRejectsMissingCustomImageWithGenericHint() throws {
    let storeRoot = try makeTempDir(files: ["state.json": "{}"])

    #expect(throws: SpawnError.self) {
        _ = try ManagedImagePolicy.resolve(
            detection: ToolchainDetector.Inspection(toolchain: .go, source: .goMod),
            toolchainOverride: nil,
            imageOverride: "ghcr.io/example/custom:latest",
            storeRoot: storeRoot
        )
    }
}

@Test func managedImagePolicyWarnsWhenImageStoreCannotBeRead() throws {
    let storeRoot = try makeTempDir(files: [:])

    let resolution = try ManagedImagePolicy.resolve(
        detection: ToolchainDetector.Inspection(toolchain: .rust, source: .cargo),
        toolchainOverride: nil,
        imageOverride: nil,
        storeRoot: storeRoot
    )

    #expect(resolution.warnings.count == 1)
    #expect(resolution.warnings[0].contains("Unable to verify whether spawn-rust:latest exists"))
}
