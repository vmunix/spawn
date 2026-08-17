import Testing

@testable import spawn

@Test func workspacePlanResolvesTheCompleteRuntimeInput() throws {
    let workspace = Mount(hostPath: "/code/project", readOnly: false)
    let agentState = Mount(
        hostPath: "/state/codex",
        guestPath: "/home/coder/.codex",
        readOnly: false
    )
    let cache = Mount(
        hostPath: "/state/caches/project/cargo-registry",
        guestPath: "/opt/rust/cargo/registry",
        readOnly: false
    )

    let plan = try ResolvedLaunchPlan.workspace(
        image: "spawn-rust:latest",
        resolvedMounts: [workspace, agentState],
        preparedCacheMounts: [cache],
        environment: ["SPAWN_SAFE_MODE": "1"],
        entrypoint: ["cargo", "test"],
        cpus: 6,
        memory: "12g",
        allocateTerminal: true
    )

    #expect(plan.image == "spawn-rust:latest")
    #expect(plan.mounts == [workspace, agentState, cache])
    #expect(plan.environment == ["SPAWN_SAFE_MODE": "1"])
    #expect(plan.workdir == workspace.guestPath)
    #expect(plan.entrypoint == ["cargo", "test"])
    #expect(plan.resources == .init(cpus: 6, memory: "12g"))
    #expect(plan.io == .init(keepStandardInputOpen: true, allocateTerminal: true))
    #expect(plan.removeOnExit)
}

@Test func workspacePlanRequiresAPrimaryWorkspaceMount() {
    #expect(throws: SpawnError.self) {
        try ResolvedLaunchPlan.workspace(
            image: "spawn-base:latest",
            resolvedMounts: [],
            preparedCacheMounts: [],
            environment: [:],
            entrypoint: ["true"],
            cpus: 4,
            memory: "8g",
            allocateTerminal: false
        )
    }
}
