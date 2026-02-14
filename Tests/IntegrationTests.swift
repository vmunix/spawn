import Testing
@testable import ccc

@Test func fullPipelineProducesCorrectArguments() throws {
    let target = try makeTempDir(files: ["Cargo.toml": ""])

    // Detect toolchain
    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .rust)

    // Resolve image
    let image = ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "ccc-rust:latest")

    // Resolve mounts
    let mounts = MountResolver.resolve(
        target: target, additional: [], readOnly: [], includeGit: false, agent: "claude-code"
    )
    #expect(mounts[0].guestPath.hasPrefix("/workspace/"))

    // Build args
    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: mounts,
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.claudeCode.entrypoint,
        cpus: 4,
        memory: "8g"
    )

    #expect(args.first == "run")
    #expect(args.contains("ccc-rust:latest"))
    #expect(args.contains("claude"))
    #expect(args.contains("--dangerously-skip-permissions"))
}

@Test func fullPipelineWithGoProject() throws {
    let target = try makeTempDir(files: ["go.mod": "module example.com/app"])

    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .go)

    let image = ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "ccc-go:latest")

    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: [Mount(hostPath: target.path, readOnly: false)],
        env: [:],
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.codex.entrypoint,
        cpus: 2,
        memory: "4g"
    )

    #expect(args.contains("ccc-go:latest"))
    #expect(args.contains("codex"))
    #expect(args.contains { $0.contains("--cpus") })
}
