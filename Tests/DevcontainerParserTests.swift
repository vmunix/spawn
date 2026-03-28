import Testing

@testable import spawn

@Test func parsesImageField() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"image": "mcr.microsoft.com/devcontainers/rust:1"}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config != nil)
    #expect(config?.toolchain == .rust)
    #expect(config?.image == "mcr.microsoft.com/devcontainers/rust:1")
}

@Test func parsesDockerfileField() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"build": {"dockerfile": "Dockerfile.dev"}}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config != nil)
    #expect(config?.toolchain == nil)
    #expect(config?.dockerfile == "Dockerfile.dev")
}

@Test func parsesFeaturesField() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"features": {"ghcr.io/devcontainers/features/go:1": {}}}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config != nil)
    #expect(config?.toolchain == .go)
}

@Test func parsesNodeImageAsJavaScriptToolchain() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"image": "mcr.microsoft.com/devcontainers/typescript-node:1-22-bookworm"}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config != nil)
    #expect(config?.toolchain == .js)
}

@Test func parsesDenoFeatureAsJavaScriptToolchain() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"features": {"ghcr.io/devcontainers/features/deno:1": {}}}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config != nil)
    #expect(config?.toolchain == .js)
}

@Test func parsesContainerEnv() throws {
    let dir = try makeTempDir(files: [
        "devcontainer.json": """
        {"image": "ubuntu:24.04", "containerEnv": {"FOO": "bar"}}
        """
    ])
    let config = DevcontainerConfig.parse(at: dir.appendingPathComponent("devcontainer.json"))
    #expect(config?.env["FOO"] == "bar")
}
