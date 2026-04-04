import Foundation
import Testing

@testable import spawn

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
    #expect(detail.contains("[workspace defaults: agent=codex, access=git]"))
}

@Test func workspaceDetailOmitsWorkspaceDefaultsWhenUnset() {
    let detail = Spawn.Doctor.workspaceDetail(
        path: fileURL("/Users/me/code/project"),
        inspection: ToolchainDetector.Inspection(toolchain: .base, source: .fallback),
        workspaceConfig: nil
    )

    #expect(detail == "/Users/me/code/project -> spawn-base:latest (fallback)")
}

@Test func workspaceDetailExplainsDockerfileRuntimeOptIn() {
    let detail = Spawn.Doctor.workspaceDetail(
        path: fileURL("/Users/me/code/project"),
        inspection: ToolchainDetector.Inspection(toolchain: nil, source: .dockerfile),
        workspaceConfig: nil
    )

    #expect(detail.contains("pass '--runtime spawn'"))
    #expect(detail.contains("'--runtime workspace-image'"))
}
