import Testing

@testable import spawn

@Test func detectsRustFromCargoToml() throws {
    let dir = try makeTempDir(files: ["Cargo.toml": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .rust)
}

@Test func detectsGoFromGoMod() throws {
    let dir = try makeTempDir(files: ["go.mod": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .go)
}

@Test func detectsCppFromCMakeLists() throws {
    let dir = try makeTempDir(files: ["CMakeLists.txt": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func detectsJavaScriptFromPackageJSON() throws {
    let dir = try makeTempDir(files: ["package.json": "{\"name\":\"app\"}"])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: .js, source: .packageJSON))
}

@Test func detectsJavaScriptFromBunLock() throws {
    let dir = try makeTempDir(files: ["bun.lock": ""])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: .js, source: .bunLock))
}

@Test func detectsJavaScriptFromDenoConfig() throws {
    let dir = try makeTempDir(files: ["deno.json": "{\"tasks\":{}}"])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: .js, source: .denoConfig))
}

@Test func prefersRustOverPackageJSONInMixedRepo() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        "package.json": "{\"name\":\"ui\"}",
    ])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: .rust, source: .cargo))
}

@Test func makefileAloneFallsToBase() throws {
    let dir = try makeTempDir(files: ["Makefile": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .base)
}

@Test func fallsBackToBase() throws {
    let dir = try makeTempDir(files: ["README.md": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .base)
}

@Test func prefersDevcontainerOverAutoDetect() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        ".devcontainer/devcontainer.json": """
        {"image": "mcr.microsoft.com/devcontainers/go:1.23"}
        """,
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .go)
}

@Test func prefersSpawnTomlOverAll() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        ".spawn.toml": """
        [toolchain]
        base = "cpp"
        """,
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func detectsDockerfile() throws {
    let dir = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == nil)
}

@Test func spawnTomlIgnoresOtherSections() throws {
    let dir = try makeTempDir(files: [
        ".spawn.toml": """
        [agent]
        base_url = "https://example.com"

        [toolchain]
        base = "rust"
        """
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .rust)
}

@Test func inspectReportsSpawnTomlSource() throws {
    let dir = try makeTempDir(files: [
        ".spawn.toml": """
        [toolchain]
        base = "go"
        """
    ])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: .go, source: .spawnToml))
}

@Test func inspectReportsDockerfileSource() throws {
    let dir = try makeTempDir(files: ["Containerfile": "FROM ubuntu:24.04"])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile))
}

@Test func inspectReportsDevcontainerDockerfileSource() throws {
    let dir = try makeTempDir(files: [
        ".devcontainer/devcontainer.json": """
        {"build": {"dockerfile": "Dockerfile.dev"}}
        """
    ])
    let result = ToolchainDetector.inspect(in: dir)
    #expect(result == ToolchainDetector.Inspection(toolchain: nil, source: .devcontainerDockerfile))
}

@Test func loadsWorkspaceDefaultsFromSpawnToml() throws {
    let dir = try makeTempDir(files: [
        ".spawn.toml": """
        [workspace]
        agent = "codex"
        access = "git"

        [toolchain]
        base = "rust"
        """
    ])

    let config = ToolchainDetector.loadWorkspaceConfig(in: dir)
    #expect(config?.agentName == "codex")
    #expect(config?.accessName == "git")
    #expect(config?.toolchain == .rust)
}
