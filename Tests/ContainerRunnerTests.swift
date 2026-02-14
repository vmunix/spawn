import Testing
@testable import ccc

@Test func buildsBasicRunArguments() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [Mount(hostPath: "/Users/me/code/project", readOnly: false)],
        env: ["KEY": "value"],
        workdir: "/workspace/project",
        entrypoint: ["claude"],
        cpus: 4,
        memory: "8g"
    )

    #expect(args.contains("run"))
    #expect(args.contains("--rm"))
    #expect(args.contains("ccc-base:latest"))
    #expect(args.contains("claude"))
}

@Test func includesAllMounts() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-rust:latest",
        mounts: [
            Mount(hostPath: "/code/project", readOnly: false),
            Mount(hostPath: "/code/lib", readOnly: true),
            Mount(hostPath: "/root/.gitconfig", guestPath: "/root/.gitconfig", readOnly: true),
        ],
        env: [:],
        workdir: "/workspace/project",
        entrypoint: ["claude"],
        cpus: 4,
        memory: "8g"
    )

    let volumeCount = args.enumerated().filter { $0.element == "--volume" }.count
    #expect(volumeCount == 3)
}

@Test func includesEnvVars() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [],
        env: ["ANTHROPIC_API_KEY": "sk-123", "FOO": "bar"],
        workdir: "/workspace/test",
        entrypoint: ["claude"],
        cpus: 2,
        memory: "4g"
    )

    let envCount = args.enumerated().filter { $0.element == "--env" }.count
    #expect(envCount == 2)
}

@Test func shellModeOverridesEntrypoint() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["/bin/bash"],
        cpus: 4,
        memory: "8g"
    )

    #expect(args.last == "/bin/bash")
}
