import Testing
@testable import spawn

@Test func resolvesTargetDirectory() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: [],
        includeGit: false,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/project" && !$0.readOnly })
}

@Test func includesAdditionalMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: ["/Users/me/code/lib"],
        readOnly: [],
        includeGit: false,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/lib" && !$0.readOnly })
}

@Test func includesReadOnlyMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: ["/Users/me/code/docs"],
        includeGit: false,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/docs" && $0.readOnly })
}

@Test func noGitExcludesGitMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: false,
        agent: "claude-code"
    )
    let gitMounts = mounts.filter { $0.guestPath.contains(".git") || $0.guestPath.contains(".ssh") }
    #expect(gitMounts.isEmpty)
}

@Test func mountsClaudeCodeCredentialState() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: false,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.guestPath == "/home/coder/.claude" && !$0.readOnly })
    #expect(mounts.contains { $0.guestPath == "/home/coder/.claude-state" && !$0.readOnly })
}

@Test func mountsCodexCredentialState() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: false,
        agent: "codex"
    )
    #expect(mounts.contains { $0.guestPath == "/home/coder/.codex" && !$0.readOnly })
}
