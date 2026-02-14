import Testing
@testable import ccc

@Test func resolvesImageFromToolchain() {
    let image = ImageResolver.resolve(toolchain: .rust, imageOverride: nil)
    #expect(image == "ccc-rust:latest")
}

@Test func resolvesBaseImage() {
    let image = ImageResolver.resolve(toolchain: .base, imageOverride: nil)
    #expect(image == "ccc-base:latest")
}

@Test func overrideWins() {
    let image = ImageResolver.resolve(toolchain: .rust, imageOverride: "my-custom:v1")
    #expect(image == "my-custom:v1")
}

@Test func cppImage() {
    let image = ImageResolver.resolve(toolchain: .cpp, imageOverride: nil)
    #expect(image == "ccc-cpp:latest")
}
