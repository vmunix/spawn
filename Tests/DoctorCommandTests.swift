import ArgumentParser
import Foundation
import Testing

@testable import spawn

@Test func resolveWorkspacePathPrefersCwdOption() throws {
    let currentDirectory = fileURL("/Users/me/code/current")
    let resolved = try Spawn.Doctor.resolveWorkspacePath(
        cwd: "/Users/me/code/other",
        path: nil,
        currentDirectory: currentDirectory
    )

    #expect(resolved.path == "/Users/me/code/other")
}

@Test func resolveWorkspacePathAcceptsPositionalPath() throws {
    let currentDirectory = fileURL("/Users/me/code/current")
    let resolved = try Spawn.Doctor.resolveWorkspacePath(
        cwd: nil,
        path: "/Users/me/code/project",
        currentDirectory: currentDirectory
    )

    #expect(resolved.path == "/Users/me/code/project")
}

@Test func resolveWorkspacePathRejectsConflictingSelectors() {
    #expect(throws: ValidationError.self) {
        try Spawn.Doctor.resolveWorkspacePath(
            cwd: "/Users/me/code/one",
            path: "/Users/me/code/two",
            currentDirectory: fileURL("/Users/me/code/current")
        )
    }
}

@Test func parseSystemStatusReadsStatusAndAppRoot() {
    let output = """
        FIELD              VALUE
        status             running
        appRoot            /Users/me/Library/Application Support/com.apple.container/
        installRoot        /opt/homebrew/Cellar/container/0.11.0/
        """

    let status = Spawn.Doctor.parseSystemStatus(output)
    #expect(
        status
            == Spawn.Doctor.SystemStatus(
                status: "running",
                appRoot: "/Users/me/Library/Application Support/com.apple.container/"
            )
    )
}

@Test func parseSystemStatusReturnsNilWithoutStatusField() {
    let output = """
        FIELD              VALUE
        appRoot            /Users/me/Library/Application Support/com.apple.container/
        """

    #expect(Spawn.Doctor.parseSystemStatus(output) == nil)
}

@Test func workspaceDetailIncludesWorkspaceDefaults() {
    let detail = Spawn.Doctor.workspaceDetail(
        path: fileURL("/Users/me/code/project"),
        inspection: ToolchainDetector.Inspection(toolchain: .rust, source: .spawnToml),
        workspaceConfig: WorkspaceConfig(
            toolchainName: "rust",
            agentName: "codex",
            accessName: "git"
        )
    )

    #expect(detail.contains("/Users/me/code/project -> spawn-rust:latest from .spawn.toml"))
    #expect(detail.contains("[workspace config: agent=codex, access=git (explicit --access required)]"))
}

@Test func workspaceDetailOmitsWorkspaceDefaultsWhenUnset() {
    let detail = Spawn.Doctor.workspaceDetail(
        path: fileURL("/Users/me/code/project"),
        inspection: ToolchainDetector.Inspection(toolchain: .base, source: .fallback),
        workspaceConfig: nil
    )

    #expect(detail == "/Users/me/code/project -> spawn-base:latest (fallback)")
}

@Test func workspaceDetailExplainsDockerfileRuntimeOptIn() throws {
    let workspace = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let detail = Spawn.Doctor.workspaceDetail(
        path: workspace,
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile),
        workspaceConfig: nil
    )

    #expect(detail.contains("Use '--runtime workspace-image'"))
    #expect(detail.contains("or '--runtime spawn'"))
    #expect(detail.contains(WorkspaceImageRuntime.imageName(for: workspace)))
    #expect(detail.contains("dockerfile="))
    #expect(detail.contains("context="))
    #expect(detail.contains("cache="))
}

@Test func workspaceRuntimeDetailIncludesTrackedPathsAndCachedState() throws {
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

    let detail = Spawn.Doctor.workspaceRuntimeDetail(
        path: workspace,
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile),
        stateDir: stateDir,
        storeRoot: storeRoot
    )

    #expect(detail.contains("cached, up to date"))
    #expect(detail.contains(plan.dockerfile.path))
    #expect(detail.contains(plan.context.path))
    #expect(detail.contains(plan.cacheRecord.path))
}

@Test func workspaceRuntimeDetailIncludesDevcontainerConfigPath() throws {
    let workspace = try makeTempDir(files: [
        ".devcontainer/devcontainer.json": """
        {"build": {"dockerfile": "Dockerfile.dev", "context": ".."}}
        """,
        ".devcontainer/Dockerfile.dev": "FROM ubuntu:24.04",
    ])
    let stateDir = try makeTempDir(files: [:])
    let detail = Spawn.Doctor.workspaceRuntimeDetail(
        path: workspace,
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .devcontainerDockerfile),
        stateDir: stateDir,
        storeRoot: try makeTempDir(files: [:])
    )

    #expect(detail.contains("config="))
    #expect(detail.contains(workspace.appendingPathComponent(".devcontainer/devcontainer.json").path))
}

@Test func workspaceRuntimeCacheStatusReflectsReadyState() throws {
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

    let status = Spawn.Doctor.workspaceRuntimeCacheStatus(
        path: workspace,
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile),
        stateDir: stateDir,
        storeRoot: storeRoot
    )
    #expect(status == .ready)
}

@Test func workspaceReportIncludesStructuredRuntimeData() throws {
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

    let report = Spawn.Doctor.workspaceReport(
        path: workspace,
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile),
        workspaceConfig: WorkspaceConfig(toolchainName: nil, agentName: "codex", accessName: "git"),
        stateDir: stateDir,
        storeRoot: storeRoot
    )

    #expect(report.source == "dockerfile")
    #expect(report.defaults == Spawn.Doctor.WorkspaceDefaultsReport(agent: "codex", access: "git"))
    #expect(report.runtime?.cacheStatus == "ready")
    #expect(report.runtime?.dockerfilePath == plan.dockerfile.path)
    #expect(report.runtime?.cacheRecordPath == plan.cacheRecord.path)
}

@Test func renderJSONIncludesStructuredWorkspaceRuntime() throws {
    let report = Spawn.Doctor.Report(
        checks: [
            Spawn.Doctor.CheckReport(
                status: .ok,
                title: "Workspace",
                detail: "ready"
            )
        ],
        workspace: Spawn.Doctor.WorkspaceReport(
            path: "/tmp/project",
            source: "dockerfile",
            detail: "detail",
            defaults: Spawn.Doctor.WorkspaceDefaultsReport(agent: "codex", access: "git"),
            runtime: Spawn.Doctor.WorkspaceRuntimeReport(
                image: "spawn-workspace-demo:latest",
                cacheStatus: "stale",
                cacheReason: "build inputs changed",
                dockerfilePath: "/tmp/project/Dockerfile",
                contextPath: "/tmp/project",
                configPath: nil,
                cacheRecordPath: "/tmp/cache.json"
            )
        )
    )

    let json = try Spawn.Doctor.renderJSON(report)
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let workspace = try #require(object["workspace"] as? [String: Any])
    let runtime = try #require(workspace["runtime"] as? [String: Any])
    let checks = try #require(object["checks"] as? [[String: Any]])

    #expect(workspace["source"] as? String == "dockerfile")
    #expect(runtime["cacheStatus"] as? String == "stale")
    #expect(runtime["cacheReason"] as? String == "build inputs changed")
    #expect(checks.first?["status"] as? String == "ok")
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
