import Foundation
import Testing

@testable import spawn

@Test func buildsBasicRunArguments() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [Mount(hostPath: "/Users/me/code/project", readOnly: false)],
            env: ["KEY": "value"],
            workdir: "/workspace/project",
            entrypoint: ["claude"],
            cpus: 4,
            memory: "8g"
        ))

    #expect(args.contains("run"))
    #expect(args.contains("--rm"))
    #expect(args.contains("spawn-base:latest"))
    #expect(args.contains("claude"))
}

@Test func includesAllMounts() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-rust:latest",
            mounts: [
                Mount(hostPath: "/code/project", readOnly: false),
                Mount(hostPath: "/code/lib", readOnly: true),
                Mount(hostPath: "/home/user/.gitconfig", guestPath: "/home/coder/.gitconfig", readOnly: true),
            ],
            env: [:],
            workdir: "/workspace/project",
            entrypoint: ["claude"],
            cpus: 4,
            memory: "8g"
        ))

    let volumeCount = args.enumerated().filter { $0.element == "--volume" }.count
    #expect(volumeCount == 3)
}

@Test func includesEnvVars() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: ["ANTHROPIC_API_KEY": "sk-123", "FOO": "bar"],
            workdir: "/workspace/test",
            entrypoint: ["claude"],
            cpus: 2,
            memory: "4g"
        ))

    let envCount = args.enumerated().filter { $0.element == "--env" }.count
    #expect(envCount == 2)
}

@Test func shellModeOverridesEntrypoint() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: [:],
            workdir: "/workspace/test",
            entrypoint: ["/bin/bash"],
            cpus: 4,
            memory: "8g"
        ))

    #expect(args.last == "/bin/bash")
}

@Test func launchPlanControlsLifecycleAndTerminalFlags() {
    let interactive = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: [:],
            workdir: "/workspace/test",
            entrypoint: ["true"],
            cpus: 4,
            memory: "8g",
            allocateTerminal: true
        ))
    let noninteractive = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: [:],
            workdir: "/workspace/test",
            entrypoint: ["true"],
            cpus: 4,
            memory: "8g",
            keepStandardInputOpen: false,
            removeOnExit: false
        ))

    #expect(interactive.contains("--rm"))
    #expect(interactive.contains("-i"))
    #expect(interactive.contains("-t"))
    #expect(!noninteractive.contains("--rm"))
    #expect(!noninteractive.contains("-i"))
    #expect(!noninteractive.contains("-t"))
}

// MARK: - Safe mode env var tests

@Test func safeModeIncludesSafeEnvVar() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: ["SPAWN_SAFE_MODE": "1"],
            workdir: "/workspace/test",
            entrypoint: ["claude"],
            cpus: 4,
            memory: "8g",
        ))

    let envArgs = zip(args, args.dropFirst()).filter { $0.0 == "--env" }.map(\.1)
    #expect(envArgs.contains("SPAWN_SAFE_MODE=1"))
}

@Test func yoloModeOmitsSafeEnvVar() {
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: [:],
            workdir: "/workspace/test",
            entrypoint: ["claude", "--dangerously-skip-permissions"],
            cpus: 4,
            memory: "8g",
        ))

    let envArgs = zip(args, args.dropFirst()).filter { $0.0 == "--env" }.map(\.1)
    #expect(!envArgs.contains("SPAWN_SAFE_MODE=1"))
}

@Test func buildArgsRendersEnvironmentInSortedKeyOrder() {
    // A dictionary has no order of its own, so the sort is the only thing making
    // the logged and executed container command reproducible between runs. The
    // keys here are deliberately unsorted in the literal.
    let args = ContainerRunner.buildArgs(
        for: makeLaunchPlan(
            image: "spawn-base:latest",
            mounts: [],
            env: ["ZULU": "3", "ALPHA": "1", "MIKE": "2"],
            workdir: "/workspace/test",
            entrypoint: ["true"],
            cpus: 4,
            memory: "8g"
        ))

    let envArgs = zip(args, args.dropFirst()).filter { $0.0 == "--env" }.map(\.1)
    #expect(envArgs == ["ALPHA=1", "MIKE=2", "ZULU=3"])
}

// MARK: - Build caches in the container argv

@Test func buildArgsBindMountsBuildCachesAfterTheWorkspace() throws {
    // Resolve the same typed plan Run hands to ContainerRunner, then render it.
    // Testing CacheMounts alone would stay green if final plan assembly dropped
    // the caches.
    let caches = CacheMounts.forToolchain(
        .rust,
        scope: .workspace,
        workspace: URL(fileURLWithPath: "/Users/me/code/project"),
        root: URL(fileURLWithPath: "/state/caches")
    )
    let workspaceMount = Mount(hostPath: "/code/project", readOnly: false)
    let plan = try ResolvedLaunchPlan.workspace(
        image: "spawn-rust:latest",
        resolvedMounts: [workspaceMount],
        preparedCacheMounts: caches,
        environment: [:],
        entrypoint: ["true"],
        cpus: 4,
        memory: "8g",
        allocateTerminal: false
    )
    let args = ContainerRunner.buildArgs(for: plan)

    #expect(caches.count == 2)
    #expect(plan.mounts == [workspaceMount] + caches)
    // The rendered working directory, not just the derived one: it comes from the
    // primary mount, and the cache mounts appended after it must not displace it.
    let workdirValues = zip(args, args.dropFirst()).filter { $0.0 == "--workdir" }.map(\.1)
    #expect(plan.workdir == "/workspace/project")
    #expect(workdirValues == [plan.workdir])
    let volumeSpecs = zip(args, args.dropFirst()).filter { $0.0 == "--volume" }.map(\.1)
    #expect(
        volumeSpecs == ["/code/project:/workspace/project"] + caches.map { "\($0.hostPath):\($0.guestPath)" }
    )
    // Never `:ro`: a read-only cache would fail every fetch that populates it.
    #expect(!volumeSpecs.contains { $0.hasSuffix(":ro") })
    #expect(volumeSpecs.contains("/state/caches/project-\(WorkspaceIdentity.fnv1a64Hex("/Users/me/code/project"))/cargo-registry:/opt/rust/cargo/registry"))
}

// MARK: - Preflight tests

@Test func preflightThrowsForMissingBinary() throws {
    #expect(throws: SpawnError.self) {
        try ContainerRunner.preflight(containerPath: "/nonexistent/path/to/container")
    }
}

@Test func preflightThrowsForNonExecutableFile() throws {
    let dir = try makeTempDir(files: ["not-executable": "just a file"])
    let path = dir.appendingPathComponent("not-executable").path

    #expect(throws: SpawnError.self) {
        try ContainerRunner.preflight(containerPath: path)
    }
}

@Test func preflightThrowsForFailingBinary() throws {
    let dir = try makeTempDir(files: ["failing-bin": "#!/bin/sh\nexit 1\n"])
    let path = dir.appendingPathComponent("failing-bin").path
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

    #expect(throws: SpawnError.self) {
        try ContainerRunner.preflight(containerPath: path)
    }
}

@Test func preflightSucceedsForWorkingBinary() throws {
    // Use a real signed binary that ignores arguments and exits 0
    try ContainerRunner.preflight(containerPath: "/usr/bin/true")
}

@Test func resolveExecutablePathFindsBinaryViaPATH() throws {
    let dir = try makeTempDir(files: ["container": "#!/bin/sh\nexit 0\n"])
    let path = dir.appendingPathComponent("container").path
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)

    let resolved = ContainerRunner.resolveExecutablePath(
        "container",
        searchPath: dir.path
    )

    #expect(resolved == path)
}
