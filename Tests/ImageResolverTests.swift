import Testing

@testable import spawn

@Test func resolvesImageFromToolchain() throws {
    let image = try ImageResolver.resolve(toolchain: .rust, imageOverride: nil)
    #expect(image == "spawn-rust:latest")
}

@Test func resolvesBaseImage() throws {
    let image = try ImageResolver.resolve(toolchain: .base, imageOverride: nil)
    #expect(image == "spawn-base:latest")
}

@Test func overrideWins() throws {
    let image = try ImageResolver.resolve(toolchain: .rust, imageOverride: "my-custom:v1")
    #expect(image == "my-custom:v1")
}

@Test func cppImage() throws {
    let image = try ImageResolver.resolve(toolchain: .cpp, imageOverride: nil)
    #expect(image == "spawn-cpp:latest")
}

@Test func rejectsInvalidImageReference() {
    let hex64 = String(repeating: "a", count: 64)
    #expect(throws: Error.self) {
        try ImageResolver.resolve(toolchain: .base, imageOverride: hex64)
    }
}

@Test func acceptsRegistryOverride() throws {
    let image = try ImageResolver.resolve(toolchain: .base, imageOverride: "ghcr.io/myorg/myimage:v1")
    #expect(image == "ghcr.io/myorg/myimage:v1")
}
