import Testing

@testable import spawn

@Test func resolvesTargetDirectory() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: [],
        access: .minimal,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/project" && !$0.readOnly })
}

@Test func includesAdditionalMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: ["/Users/me/code/lib"],
        readOnly: [],
        access: .minimal,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/lib" && !$0.readOnly })
}

@Test func includesReadOnlyMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: ["/Users/me/code/docs"],
        access: .minimal,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/docs" && $0.readOnly })
}

@Test func minimalAccessExcludesHostCredentialMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .minimal,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.guestPath == "/home/coder/.gitconfig-dir" } == false)
    #expect(mounts.contains { $0.guestPath == "/home/coder/.ssh" } == false)
    #expect(mounts.contains { $0.guestPath == "/home/coder/.config/gh" } == false)
}

@Test func gitAccessExcludesSSHMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .git,
        agent: "claude-code"
    )
    #expect(mounts.contains { $0.guestPath == "/home/coder/.ssh" } == false)
}

@Test func mountsClaudeCodeCredentialState() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .minimal,
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
        access: .minimal,
        agent: "codex"
    )
    #expect(mounts.contains { $0.guestPath == "/home/coder/.codex" && !$0.readOnly })
}
