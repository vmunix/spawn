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
        accessName: "trusted",
        cacheName: nil
    )

    #expect(
        RunRuntimePolicy.effectiveAccessName(
            accessOverride: nil,
            workspaceConfig: workspaceConfig
        ) == AccessProfile.minimal.rawValue
    )
}

@Test func effectiveAccessNameStillHonorsExplicitCLIOverride() {
    let workspaceConfig = WorkspaceConfig(
        toolchainName: nil,
        agentName: "codex",
        accessName: "trusted",
        cacheName: nil
    )

    #expect(
        RunRuntimePolicy.effectiveAccessName(
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
    #expect(RunRuntimePolicy.requiresExplicitRuntimeSelection(for: .dockerfile) == true)
    #expect(RunRuntimePolicy.requiresExplicitRuntimeSelection(for: .devcontainerDockerfile) == true)
    #expect(RunRuntimePolicy.requiresExplicitRuntimeSelection(for: .cargo) == false)
}

@Test func rebuildWorkspaceImageFlagRequiresWorkspaceImageRuntime() {
    #expect(throws: ValidationError.self) {
        try RunRuntimePolicy.validateOptions(
            runtimeMode: .spawn,
            image: nil,
            toolchain: nil,
            rebuildWorkspaceImage: true
        )
    }
}

@Test func workspaceImageRuntimeRejectsToolchainAndImageOverrides() {
    #expect(throws: ValidationError.self) {
        try RunRuntimePolicy.validateOptions(
            runtimeMode: .workspaceImage,
            image: nil,
            toolchain: "rust",
            rebuildWorkspaceImage: false
        )
    }

    #expect(throws: ValidationError.self) {
        try RunRuntimePolicy.validateOptions(
            runtimeMode: .workspaceImage,
            image: "custom:latest",
            toolchain: nil,
            rebuildWorkspaceImage: false
        )
    }
}

@Test func launchSummaryIncludesCoreContext() {
    let workspace = URL(fileURLWithPath: "/Users/me/code/project")
    let lines = RunLaunchSummary.lines(
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
    let lines = RunLaunchSummary.lines(
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
    let lines = RunLaunchSummary.lines(
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
    let lines = RunLaunchSummary.lines(
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
    let lines = RunLaunchSummary.lines(
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
    let lines = RunLaunchSummary.lines(
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

// MARK: - Cache scope precedence
//
// Sharing a build cache is a cross-workspace read-write channel, so the default
// is the private scope and only an explicit flag may widen it — the rule
// `access` already follows. Every assertion below is anchored on the resolved
// scope, not on message text.

@Test func cacheScopeDefaultsToTheWorkspacePrivateScope() throws {
    let name = RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: nil)
    #expect(try CacheScope.parse(name) == .workspace)

    let configWithoutCache = WorkspaceConfig(
        toolchainName: nil,
        agentName: "codex",
        accessName: "git",
        cacheName: nil
    )
    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: configWithoutCache)
        ) == .workspace
    )
}

@Test func repoConfiguredSharingIsIgnoredWithoutTheFlag() throws {
    // The security rule: a repo cannot widen its own cache reach. A cloned
    // workspace that sets cache = "shared" would otherwise reach the caches a
    // user had opted into sharing elsewhere.
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")

    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: config)
        ) == .workspace
    )
    #expect(
        RunRuntimePolicy.ignoredConfiguredCacheScope(cacheOverride: nil, workspaceConfig: config) == .shared
    )
}

@Test func onlyTheFlagCanSelectTheSharedScope() throws {
    // The other half of the rule: the flag must actually work, or opting in
    // would be impossible and the option decorative.
    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: "shared", workspaceConfig: nil)
        ) == .shared
    )

    let privateConfig = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "workspace")
    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: "shared", workspaceConfig: privateConfig)
        ) == .shared
    )
    #expect(
        RunRuntimePolicy.ignoredConfiguredCacheScope(cacheOverride: "shared", workspaceConfig: privateConfig) == nil
    )
}

@Test func repoConfiguredNarrowingIsHonouredSilently() throws {
    // cache = "workspace" asks for less, so it is kept and nothing is reported
    // as ignored — the same asymmetry as access = "minimal".
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "workspace")

    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: config)
        ) == .workspace
    )
    #expect(RunRuntimePolicy.ignoredConfiguredCacheScope(cacheOverride: nil, workspaceConfig: config) == nil)
}

@Test func theFlagCanNarrowARepoThatAskedToShare() throws {
    let sharedConfig = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")

    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: "workspace", workspaceConfig: sharedConfig)
        ) == .workspace
    )
}

@Test func anUnusableCacheFlagIsRejectedRatherThanDefaulted() throws {
    // A typo'd --cache must not silently run with a scope the user never asked
    // for. A typo'd .spawn.toml value selects nothing, as an unknown access
    // value does, and leaves the private default in place.
    #expect(throws: ValidationError.self) {
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: "everyone", workspaceConfig: nil)
        )
    }

    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "everyone")
    #expect(
        try CacheScope.parse(
            RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: config)
        ) == .workspace
    )
    #expect(RunRuntimePolicy.ignoredConfiguredCacheScope(cacheOverride: nil, workspaceConfig: config) == nil)
}

@Test func theResolvedCacheScopeDecidesTheVolumesARunMounts() throws {
    // End of the wire: resolution must reach the names, not just the enum. A
    // repo that asks to share gets the private volumes; the flag gets the
    // shared ones, and the two sets never overlap.
    let workspace = try makeTempDir(files: [:])
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")

    let fromConfig = try CacheScope.parse(
        RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: nil, workspaceConfig: config)
    )
    let fromFlag = try CacheScope.parse(
        RunRuntimePolicy.effectiveCacheScopeName(cacheOverride: "shared", workspaceConfig: config)
    )

    let configVolumes = CacheVolumes.forRun(
        toolchain: .rust, imageOverride: nil, scope: fromConfig, workspace: workspace
    )
    let flagVolumes = CacheVolumes.forRun(
        toolchain: .rust, imageOverride: nil, scope: fromFlag, workspace: workspace
    )

    #expect(!configVolumes.isEmpty)
    #expect(Set(configVolumes.map(\.name)).isDisjoint(with: Set(flagVolumes.map(\.name))))
    #expect(configVolumes == CacheVolumes.forToolchain(.rust, scope: .workspace, workspace: workspace))
    #expect(flagVolumes == CacheVolumes.forToolchain(.rust, scope: .shared, workspace: workspace))
}
