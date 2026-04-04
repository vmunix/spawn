import Foundation
import Testing

@testable import spawn

@Test func workspaceImagePlanUsesRootDockerfile() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])

    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)

    #expect(plan.source == .dockerfile)
    #expect(plan.dockerfile.path == workspace.appendingPathComponent("Dockerfile").path)
    #expect(plan.context.path == workspace.path)
    #expect(plan.image == WorkspaceImageRuntime.imageName(for: workspace))
    #expect(plan.cacheRecord.path.hasSuffix(".json"))
}

@Test func workspaceImagePlanUsesDevcontainerBuildDefinition() throws {
    let workspace = try makeTempDir(files: [
        ".devcontainer/devcontainer.json": """
        {"build": {"dockerfile": "Dockerfile.dev", "context": ".."}, "containerEnv": {"FOO": "bar"}}
        """,
        ".devcontainer/Dockerfile.dev": "FROM ubuntu:24.04",
    ])

    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)

    #expect(plan.source == .devcontainerDockerfile)
    #expect(plan.dockerfile.path == workspace.appendingPathComponent(".devcontainer/Dockerfile.dev").path)
    #expect(plan.context.path == workspace.path)
    #expect(plan.configFile?.path == workspace.appendingPathComponent(".devcontainer/devcontainer.json").path)
    #expect(plan.env["FOO"] == "bar")
}

@Test func workspaceImageNameIsStableAndSanitized() {
    let workspace = fileURL("/Users/me/Code/My Cool Repo")

    let image = WorkspaceImageRuntime.imageName(for: workspace)

    #expect(image.hasPrefix("spawn-workspace-my-cool-repo-"))
    #expect(image.hasSuffix(":latest"))
}

@Test func workspaceImageBuildArgsIncludeDockerfileAndContext() {
    let plan = WorkspaceImageRuntime.Plan(
        image: "spawn-workspace-demo:latest",
        dockerfile: fileURL("/Users/me/code/project/Dockerfile"),
        context: fileURL("/Users/me/code/project"),
        source: .dockerfile,
        configFile: nil,
        env: [:],
        fingerprint: "abc123",
        cacheRecord: fileURL("/tmp/workspace-image.json")
    )

    let args = WorkspaceImageRuntime.buildArgs(plan: plan, cpus: 6, memory: "12g")

    let expected = [
        "build",
        "-c", "6",
        "-m", "12g",
        "-t", "spawn-workspace-demo:latest",
        "-f", "/Users/me/code/project/Dockerfile",
        "/Users/me/code/project",
    ]

    #expect(args == expected)
}

@Test func workspaceImageCacheStatusIsReadyWhenMetadataMatches() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)
    try writeCacheRecord(for: plan)

    let storeRoot = try makeTempDir(files: [
        "state.json": """
        {
            "\(plan.image)": {}
        }
        """
    ])

    let status = WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot)
    #expect(status == .ready)
}

@Test func workspaceImageCacheStatusIsNotBuiltWithoutImageOrMetadata() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)
    let storeRoot = try makeTempDir(files: [
        "state.json": "{}"
    ])

    let status = WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot)
    #expect(status == .notBuilt)
}

@Test func workspaceImageCacheStatusTurnsStaleWhenInputsChange() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let stateDir = try makeTempDir(files: [:])
    let originalPlan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)
    try writeCacheRecord(for: originalPlan)

    let storeRoot = try makeTempDir(files: [
        "state.json": """
        {
            "\(originalPlan.image)": {}
        }
        """
    ])

    try "FROM ubuntu:24.04\nRUN echo hello\n".write(
        to: workspace.appendingPathComponent("Dockerfile"),
        atomically: true,
        encoding: .utf8
    )

    let updatedPlan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)
    let status = WorkspaceImageRuntime.cacheStatus(for: updatedPlan, storeRoot: storeRoot)
    #expect(status == .stale(reason: "build inputs changed"))
}

@Test func workspaceImageCacheStatusTurnsStaleWhenImageIsMissing() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)
    try writeCacheRecord(for: plan)

    let storeRoot = try makeTempDir(files: [:])
    let status = WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot)
    #expect(status == .stale(reason: "unable to verify cached image state"))
}

@Test func workspaceImageRequestedCacheStatusCanForceRebuild() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let stateDir = try makeTempDir(files: [:])
    let plan = try WorkspaceImageRuntime.plan(for: workspace, stateDir: stateDir)

    let status = WorkspaceImageRuntime.requestedCacheStatus(
        for: plan,
        forceRebuild: true,
        storeRoot: nil
    )
    #expect(status == .stale(reason: "forced rebuild requested"))
}

private func writeCacheRecord(for plan: WorkspaceImageRuntime.Plan) throws {
    let record = WorkspaceImageRuntime.CacheRecord(
        image: plan.image,
        fingerprint: plan.fingerprint,
        source: plan.source.identifier,
        dockerfilePath: plan.dockerfile.path,
        contextPath: plan.context.path
    )
    let data = try JSONEncoder().encode(record)
    try data.write(to: plan.cacheRecord, options: .atomic)
}
