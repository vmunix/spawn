import Foundation
import Testing

@testable import spawn

@Test func fullPipelineProducesCorrectArguments() throws {
    let target = try makeTempDir(files: ["Cargo.toml": ""])

    // Detect toolchain
    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .rust)

    // Resolve image
    let image = try ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "spawn-rust:latest")

    // Resolve mounts
    let mounts = MountResolver.resolve(
        target: target, additional: [], readOnly: [], access: .minimal, agent: "claude-code"
    )
    #expect(mounts[0].guestPath.hasPrefix("/workspace/"))

    // Build args
    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: mounts,
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.claudeCode.yoloEntrypoint,
        cpus: 4,
        memory: "8g"
    )

    #expect(args.first == "run")
    #expect(args.contains("spawn-rust:latest"))
    #expect(args.contains("claude"))
    #expect(args.contains("--dangerously-skip-permissions"))
}

@Test func fullPipelineWithGoProject() throws {
    let target = try makeTempDir(files: ["go.mod": "module example.com/app"])

    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .go)

    let image = try ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "spawn-go:latest")

    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: [Mount(hostPath: target.path, readOnly: false)],
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.codex.yoloEntrypoint,
        cpus: 2,
        memory: "4g"
    )

    #expect(args.contains("spawn-go:latest"))
    #expect(args.contains("codex"))
    #expect(args.contains { $0.contains("--cpus") })
}

@Test func fullPipelineWithJavaScriptProject() throws {
    let target = try makeTempDir(files: ["bun.lock": ""])

    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .js)

    let image = try ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "spawn-js:latest")

    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: [Mount(hostPath: target.path, readOnly: false)],
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.claudeCode.safeEntrypoint,
        cpus: 2,
        memory: "4g"
    )

    #expect(args.contains("spawn-js:latest"))
    #expect(args.contains("claude"))
}

@Test func fullPipelineWithTrustedAccessIncludesCredentialVolumes() throws {
    let target = try makeTempDir(files: ["Cargo.toml": ""])
    let home = try makeTempDir(
        files: [
            ".gitconfig": "[user]\n\tname = Spawn Tester\n",
            ".config/gh/hosts.yml": "github.com:\n    oauth_token: token\n",
            ".config/gh/config.yml": "editor: vim\n",
            ".ssh/id_ed25519": "PRIVATE KEY",
        ]
    )
    let stateDir = try makeTempDir(files: [:])

    let mounts = MountResolver.resolve(
        target: target,
        additional: [],
        readOnly: [],
        access: .trusted,
        agent: "claude-code",
        stateDir: stateDir,
        homeDirectory: home
    )
    let args = ContainerRunner.buildArgs(
        image: "spawn-rust:latest",
        mounts: mounts,
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.claudeCode.safeEntrypoint,
        cpus: 4,
        memory: "8g"
    )

    #expect(args.contains("--volume"))
    #expect(args.contains("\(stateDir.appendingPathComponent("git").path):/home/coder/.gitconfig-dir:ro"))
    #expect(args.contains("\(stateDir.appendingPathComponent("gh").path):/home/coder/.config/gh:ro"))
    #expect(args.contains("\(stateDir.appendingPathComponent("ssh").path):/home/coder/.ssh:ro"))
}
