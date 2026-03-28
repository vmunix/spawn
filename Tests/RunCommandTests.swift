import Foundation
import Testing

@testable import spawn

@Test func launchSummaryIncludesCoreContext() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "codex",
        shell: false,
        yolo: false,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .rust, source: .cargo),
        resolvedToolchain: .rust,
        image: "spawn-rust:latest",
        noGit: false,
        extraMountCount: 2,
        readOnlyMountCount: 1,
        envCount: 3,
        cpus: 8,
        memory: "16g"
    )

    #expect(lines.contains("  workspace: /Users/me/code/project"))
    #expect(lines.contains("  agent: codex"))
    #expect(lines.contains("  mode: safe"))
    #expect(lines.contains("  toolchain: rust (auto-detected from Cargo.toml/rust-toolchain.toml)"))
    #expect(lines.contains("  image: spawn-rust:latest"))
    #expect(lines.contains("  extra mounts: 2 read-write, 1 read-only"))
    #expect(lines.contains("  environment: 3 variables"))
    #expect(lines.contains("  resources: 8 CPU, 16g memory"))
}

@Test func launchSummaryMarksShellSessions() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: true,
        yolo: true,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .base, source: .fallback),
        resolvedToolchain: .base,
        image: "spawn-base:latest",
        noGit: true,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 1,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  session: shell (/bin/bash)"))
    #expect(lines.contains("  mode: yolo"))
    #expect(lines.contains("  git/ssh: disabled"))
    #expect(lines.contains("  environment: 1 variable"))
}

@Test func launchSummaryIncludesSpecificJavaScriptDetectionReason() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: false,
        yolo: false,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .js, source: .bunLock),
        resolvedToolchain: .js,
        image: "spawn-js:latest",
        noGit: false,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 0,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  toolchain: js (auto-detected from bun.lock/bun.lockb)"))
}

@Test func launchSummaryMarksToolchainOverrides() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: false,
        yolo: false,
        toolchainWasOverridden: true,
        detection: ToolchainDetector.Inspection(toolchain: .go, source: .fallback),
        resolvedToolchain: .go,
        image: "spawn-go:latest",
        noGit: false,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 0,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  toolchain: go (--toolchain override)"))
}
