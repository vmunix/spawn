import Testing

@testable import spawn

@Suite struct ImageCommandTests {
    // MARK: - Remove validation

    @Test func allowsRemovingSpawnToolchainImages() {
        #expect(Spawn.Image.Remove.validateRemoval("spawn-cpp:latest") == nil)
        #expect(Spawn.Image.Remove.validateRemoval("spawn-rust:latest") == nil)
        #expect(Spawn.Image.Remove.validateRemoval("spawn-go:latest") == nil)
    }

    @Test func rejectsNonSpawnImages() {
        let result = Spawn.Image.Remove.validateRemoval("ubuntu:24.04")
        #expect(result != nil)
        #expect(result!.contains("only spawn-* images"))
    }

    @Test func rejectsSystemImages() {
        let result = Spawn.Image.Remove.validateRemoval("ghcr.io/apple/containerization/vminit:0.24.5")
        #expect(result != nil)
        #expect(result!.contains("only spawn-* images"))
    }

    @Test func rejectsSpawnBaseTagged() {
        let result = Spawn.Image.Remove.validateRemoval("spawn-base:latest")
        #expect(result != nil)
        #expect(result!.contains("depend on it"))
    }

    @Test func rejectsSpawnBaseUntagged() {
        let result = Spawn.Image.Remove.validateRemoval("spawn-base")
        #expect(result != nil)
        #expect(result!.contains("depend on it"))
    }

    @Test func allowsSpawnBaseVariants() {
        // spawn-base-foo is a different image, not the base itself
        #expect(Spawn.Image.Remove.validateRemoval("spawn-base-custom:latest") == nil)
    }
}
