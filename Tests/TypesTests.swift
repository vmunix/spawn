import Testing
@testable import ccc

@Test func mountFromHostPath() {
    let mount = Mount(hostPath: "/Users/me/code/project", readOnly: false)
    #expect(mount.guestPath == "/workspace/project")
    #expect(mount.name == "project")
}

@Test func mountFromHostPathReadOnly() {
    let mount = Mount(hostPath: "/Users/me/code/docs", readOnly: true)
    #expect(mount.readOnly == true)
    #expect(mount.guestPath == "/workspace/docs")
}

@Test func mountHandlesTrailingSlash() {
    let mount = Mount(hostPath: "/Users/me/code/project/", readOnly: false)
    #expect(mount.name == "project")
}

@Test func toolchainFromString() {
    #expect(Toolchain(rawValue: "cpp") == .cpp)
    #expect(Toolchain(rawValue: "rust") == .rust)
    #expect(Toolchain(rawValue: "go") == .go)
    #expect(Toolchain(rawValue: "base") == .base)
    #expect(Toolchain(rawValue: "invalid") == nil)
}

@Test func builtInAgentProfiles() {
    let claude = AgentProfile.claudeCode
    #expect(claude.name == "claude-code")
    #expect(claude.entrypoint.contains("--dangerously-skip-permissions"))

    let codex = AgentProfile.codex
    #expect(codex.name == "codex")
    #expect(codex.entrypoint.contains("--full-auto"))
}
