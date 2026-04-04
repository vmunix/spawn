import Foundation
import Testing

@testable import spawn

private func posixPermissions(of path: String) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    guard let value = attrs[.posixPermissions] as? NSNumber else {
        Issue.record("Missing POSIX permissions for \(path)")
        return -1
    }
    return value.intValue & 0o777
}

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

@Test func gitAccessIncludesGitAndGitHubCredentialMounts() throws {
    let home = try makeTempDir(
        files: [
            ".gitconfig": "[user]\n\tname = Spawn Tester\n",
            ".config/gh/hosts.yml": "github.com:\n    oauth_token: token\n",
            ".config/gh/config.yml": "editor: vim\n",
            ".config/gh/notes.txt": "ignore me\n",
        ]
    )
    let stateDir = try makeTempDir(files: [:])

    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .git,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
    )

    #expect(mounts.contains { $0.guestPath == "/home/coder/.gitconfig-dir" && $0.readOnly })
    #expect(mounts.contains { $0.guestPath == "/home/coder/.config/gh" && $0.readOnly })
    #expect(mounts.contains { $0.guestPath == "/home/coder/.ssh" } == false)

    #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("git/.gitconfig").path))
    #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("gh/hosts.yml").path))
    #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("gh/config.yml").path))
    #expect(FileManager.default.fileExists(atPath: stateDir.appendingPathComponent("gh/notes.txt").path) == false)
}

@Test func trustedAccessCopiesSSHWithFilteringAndPermissions() throws {
    let home = try makeTempDir(
        files: [
            ".gitconfig": "[user]\n\tname = Spawn Tester\n",
            ".ssh/id_ed25519": "PRIVATE KEY",
            ".ssh/id_ed25519.pub": "PUBLIC KEY",
            ".ssh/config": "Host *\n  ServerAliveInterval 60\n",
            ".ssh/known_hosts": "example.com ssh-ed25519 AAAA\n",
            ".ssh/random-secret.txt": "ignore top-level nonstandard files\n",
            ".ssh/nested/ignored.txt": "ignore nested files\n",
            ".config/gh/hosts.yml": "github.com:\n    oauth_token: token\n",
            ".config/gh/config.yml": "editor: vim\n",
            "outside-secret.txt": "do not copy me\n",
        ]
    )
    let stateDir = try makeTempDir(files: [:])
    let symlinkPath = home.appendingPathComponent(".ssh/external-link")
    try FileManager.default.createSymbolicLink(
        at: symlinkPath,
        withDestinationURL: home.appendingPathComponent("outside-secret.txt")
    )

    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .trusted,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
    )

    #expect(mounts.contains { $0.guestPath == "/home/coder/.gitconfig-dir" && $0.readOnly })
    #expect(mounts.contains { $0.guestPath == "/home/coder/.config/gh" && $0.readOnly })
    #expect(mounts.contains { $0.guestPath == "/home/coder/.ssh" && $0.readOnly })

    let copiedSSHDir = stateDir.appendingPathComponent("ssh")
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("id_ed25519").path))
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("id_ed25519.pub").path))
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("config").path))
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("known_hosts").path))
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("random-secret.txt").path) == false)
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("nested").path) == false)
    #expect(FileManager.default.fileExists(atPath: copiedSSHDir.appendingPathComponent("external-link").path) == false)
    #expect(try posixPermissions(of: copiedSSHDir.appendingPathComponent("id_ed25519").path) == 0o600)

    let copiedGHDir = stateDir.appendingPathComponent("gh")
    #expect(FileManager.default.fileExists(atPath: copiedGHDir.appendingPathComponent("hosts.yml").path))
    #expect(FileManager.default.fileExists(atPath: copiedGHDir.appendingPathComponent("config.yml").path))
}

@Test func omitsGitMountWhenGitConfigCopyFails() throws {
    let home = try makeTempDir(files: [".gitconfig": "[user]\n\tname = Spawn Tester\n"])
    let stateDir = try makeTempDir(files: ["git": "blocking file"])

    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .git,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
    )

    #expect(mounts.contains { $0.guestPath == "/home/coder/.gitconfig-dir" } == false)
}

@Test func omitsGitHubMountWhenConfigCopyFails() throws {
    let home = try makeTempDir(files: [".config/gh/hosts.yml": "github.com:\n    oauth_token: token\n"])
    let stateRoot = try makeTempDir(files: ["blocked": "blocking file"])
    let stateDir = stateRoot.appendingPathComponent("blocked")

    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .git,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
    )

    #expect(mounts.contains { $0.guestPath == "/home/coder/.config/gh" } == false)
}

@Test func omitsSSHMountWhenCopyFails() throws {
    let home = try makeTempDir(files: [".ssh/id_ed25519": "PRIVATE KEY"])
    let stateRoot = try makeTempDir(files: ["blocked": "blocking file"])
    let stateDir = stateRoot.appendingPathComponent("blocked")

    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        access: .trusted,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
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
