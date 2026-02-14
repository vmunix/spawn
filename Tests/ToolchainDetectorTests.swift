import Testing
@testable import ccc

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

@Test func detectsCppFromMakefile() throws {
    let dir = try makeTempDir(files: ["Makefile": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
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
        """
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .go)
}

@Test func prefersCccTomlOverAll() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        ".ccc.toml": """
        [toolchain]
        base = "cpp"
        """
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func detectsDockerfile() throws {
    let dir = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == nil)
}
