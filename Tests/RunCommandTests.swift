import ArgumentParser
import Foundation
import Testing

@testable import spawn

@Test func resolveLaunchRequestDefaultsToCurrentDirectoryAndClaudeCode() throws {
    let workspace = try makeTempDir(files: [:])

    let launchRequest = try Spawn.Run.resolveLaunchRequest(
        agent: "claude-code",
        cwdOverride: nil,
        currentDirectory: workspace
    )

    #expect(launchRequest.workspace.path == workspace.standardizedFileURL.path)
    #expect(launchRequest.agent == "claude-code")
    #expect(launchRequest.workspaceConfig == nil)
}

@Test func resolveLaunchRequestTreatsKnownAgentAsAgentFromCurrentDirectory() throws {
    let workspace = try makeTempDir(files: [:])

    let launchRequest = try Spawn.Run.resolveLaunchRequest(
        agent: "codex",
        cwdOverride: nil,
        currentDirectory: workspace
    )

    #expect(launchRequest.workspace.path == workspace.standardizedFileURL.path)
    #expect(launchRequest.agent == "codex")
}

@Test func resolveLaunchRequestUsesWorkspaceConfigAgentByDefault() throws {
    let workspace = try makeTempDir(files: [
        ".spawn.toml": """
        [workspace]
        agent = "codex"
        access = "git"
        """
    ])

    let launchRequest = try Spawn.Run.resolveLaunchRequest(
        agent: nil,
        cwdOverride: nil,
        currentDirectory: workspace
    )

    #expect(launchRequest.workspace.path == workspace.standardizedFileURL.path)
    #expect(launchRequest.agent == "codex")
    #expect(launchRequest.workspaceConfig?.accessName == "git")
}

@Test func effectiveAccessNameIgnoresRepoConfiguredAccessElevation() {
    let workspaceConfig = WorkspaceConfig(
        toolchainName: nil,
        agentName: "codex",
        accessName: "trusted"
    )

    #expect(
        Spawn.Run.effectiveAccessName(
            accessOverride: nil,
            workspaceConfig: workspaceConfig
        ) == AccessProfile.minimal.rawValue
    )
}

@Test func effectiveAccessNameStillHonorsExplicitCLIOverride() {
    let workspaceConfig = WorkspaceConfig(
        toolchainName: nil,
        agentName: "codex",
        accessName: "trusted"
    )

    #expect(
        Spawn.Run.effectiveAccessName(
            accessOverride: "git",
            workspaceConfig: workspaceConfig
        ) == AccessProfile.git.rawValue
    )
}

@Test func resolveLaunchRequestUsesCwdOverrideForWorkspaceSelection() throws {
    let workspace = try makeTempDir(files: [:])

    let launchRequest = try Spawn.Run.resolveLaunchRequest(
        agent: "claude-code",
        cwdOverride: workspace.path,
        currentDirectory: fileURL("/tmp/ignored")
    )

    #expect(launchRequest.workspace.path == workspace.standardizedFileURL.path)
    #expect(launchRequest.agent == "claude-code")
}

@Test func resolveLaunchRequestRejectsUnknownAgent() throws {
    let workspace = try makeTempDir(files: [:])

    #expect(throws: ValidationError.self) {
        _ = try Spawn.Run.resolveLaunchRequest(
            agent: "not-an-agent",
            cwdOverride: nil,
            currentDirectory: workspace
        )
    }
}

@Test func resolveLaunchRequestGuidesWorkspacePathUsersToCwdFlag() throws {
    let workspace = try makeTempDir(files: [:])

    #expect(throws: ValidationError.self) {
        _ = try Spawn.Run.resolveLaunchRequest(
            agent: workspace.path,
            cwdOverride: nil,
            currentDirectory: fileURL("/tmp/ignored")
        )
    }
}

@Test func dockerfileSourcesRequireExplicitRuntimeSelection() {
    #expect(Spawn.Run.requiresExplicitRuntimeSelection(for: .dockerfile) == true)
    #expect(Spawn.Run.requiresExplicitRuntimeSelection(for: .devcontainerDockerfile) == true)
    #expect(Spawn.Run.requiresExplicitRuntimeSelection(for: .cargo) == false)
}

@Test func rebuildWorkspaceImageFlagRequiresWorkspaceImageRuntime() {
    #expect(throws: ValidationError.self) {
        try Spawn.Run.validateRuntimeOptions(
            runtimeMode: .spawn,
            image: nil,
            toolchain: nil,
            rebuildWorkspaceImage: true
        )
    }
}

@Test func workspaceImageRuntimeRejectsToolchainAndImageOverrides() {
    #expect(throws: ValidationError.self) {
        try Spawn.Run.validateRuntimeOptions(
            runtimeMode: .workspaceImage,
            image: nil,
            toolchain: "rust",
            rebuildWorkspaceImage: false
        )
    }

    #expect(throws: ValidationError.self) {
        try Spawn.Run.validateRuntimeOptions(
            runtimeMode: .workspaceImage,
            image: "custom:latest",
            toolchain: nil,
            rebuildWorkspaceImage: false
        )
    }
}

@Test func launchSummaryIncludesCoreContext() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "codex",
        shell: false,
        command: [],
        yolo: false,
        runtimeMode: .spawn,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .rust, source: .cargo),
        resolvedToolchain: .rust,
        image: "spawn-rust:latest",
        accessProfile: .git,
        extraMountCount: 2,
        readOnlyMountCount: 1,
        envCount: 3,
        cpus: 8,
        memory: "16g"
    )

    #expect(lines.contains("  workspace: /Users/me/code/project"))
    #expect(lines.contains("  agent: codex"))
    #expect(lines.contains("  mode: safe"))
    #expect(lines.contains("  runtime: spawn"))
    #expect(lines.contains("  access: git"))
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
        command: [],
        yolo: true,
        runtimeMode: .spawn,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .base, source: .fallback),
        resolvedToolchain: .base,
        image: "spawn-base:latest",
        accessProfile: .minimal,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 1,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  session: shell (/bin/bash)"))
    #expect(lines.contains("  mode: yolo"))
    #expect(lines.contains("  access: minimal"))
    #expect(lines.contains("  environment: 1 variable"))
}

@Test func launchSummaryMarksPassthroughCommands() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: false,
        command: ["cargo", "test"],
        yolo: false,
        runtimeMode: .spawn,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .rust, source: .cargo),
        resolvedToolchain: .rust,
        image: "spawn-rust:latest",
        accessProfile: .minimal,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 0,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  session: command (cargo, 1 arg)"))
}

@Test func launchSummarySummarizesCommandWithoutEchoingArguments() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: false,
        command: ["/bin/bash", "-lc", "echo super-secret-token"],
        yolo: false,
        runtimeMode: .spawn,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .base, source: .fallback),
        resolvedToolchain: .base,
        image: "spawn-base:latest",
        accessProfile: .minimal,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 0,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  session: command (/bin/bash, 2 args)"))
    #expect(lines.contains { $0.contains("super-secret-token") } == false)
}

@Test func normalizedCommandDropsLeadingSeparator() {
    #expect(Spawn.Run.normalizedCommand(["--", "cargo", "test"]) == ["cargo", "test"])
    #expect(Spawn.Run.normalizedCommand(["cargo", "test"]) == ["cargo", "test"])
}

@Test func launchSummaryIncludesSpecificJavaScriptDetectionReason() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = Spawn.Run.launchSummaryLines(
        workspace: workspace,
        agent: "claude-code",
        shell: false,
        command: [],
        yolo: false,
        runtimeMode: .spawn,
        toolchainWasOverridden: false,
        detection: ToolchainDetector.Inspection(toolchain: .js, source: .bunLock),
        resolvedToolchain: .js,
        image: "spawn-js:latest",
        accessProfile: .minimal,
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
        command: [],
        yolo: false,
        runtimeMode: .spawn,
        toolchainWasOverridden: true,
        detection: ToolchainDetector.Inspection(toolchain: .go, source: .fallback),
        resolvedToolchain: .go,
        image: "spawn-go:latest",
        accessProfile: .trusted,
        extraMountCount: 0,
        readOnlyMountCount: 0,
        envCount: 0,
        cpus: 4,
        memory: "8g"
    )

    #expect(lines.contains("  toolchain: go (--toolchain override)"))
}
