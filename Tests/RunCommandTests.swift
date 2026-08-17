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
// `access` already follows. These tests parse the real command and resolve from
// its stored properties, so disconnecting a flag at the launch boundary fails.

private func parsedRun(_ arguments: [String]) throws -> Spawn.Run {
    let command = try Spawn.Run.parseAsRoot(arguments)
    return try #require(command as? Spawn.Run)
}

/// Cache root for the resolution tests. Passed explicitly so they never derive
/// a path from the real state directory.
private let runCacheRoot = URL(fileURLWithPath: "/state/spawn/caches")

@Test func cacheScopeDefaultsToTheWorkspacePrivateScope() throws {
    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: nil)
    #expect(selection.scope == .workspace)
    #expect(selection.ignoredConfiguredScope == nil)

    let configWithoutCache = WorkspaceConfig(
        toolchainName: nil,
        agentName: "codex",
        accessName: "git",
        cacheName: nil
    )
    #expect(try parsedRun([]).resolvedCacheSelection(workspaceConfig: configWithoutCache).scope == .workspace)
}

@Test func parsedRunIgnoresRepoConfiguredSharingAndMountsPrivateCaches() throws {
    // The security rule: a repo cannot widen its own cache reach. A cloned
    // workspace that sets cache = "shared" would otherwise reach the caches a
    // user had opted into sharing elsewhere.
    let workspace = try makeTempDir(files: [:])
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")
    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: config)
    let caches = selection.mounts(toolchain: .rust, workspace: workspace, root: runCacheRoot)

    #expect(selection.scope == .workspace)
    #expect(selection.ignoredConfiguredScope == .shared)
    #expect(caches == CacheMounts.forToolchain(.rust, scope: .workspace, workspace: workspace, root: runCacheRoot))
    #expect(!caches.isEmpty)
    #expect(!caches.contains { $0.hostPath.hasPrefix(runCacheRoot.path + "/shared/") })
}

@Test func parsedCacheFlagIsTheOnlyWayToSelectSharedCaches() throws {
    // The other half of the rule: the flag must actually work, or opting in
    // would be impossible and the option decorative.
    let workspace = try makeTempDir(files: [:])
    let privateConfig = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "workspace")
    let selection = try parsedRun(["--cache", "shared"]).resolvedCacheSelection(workspaceConfig: privateConfig)
    let caches = selection.mounts(toolchain: .rust, workspace: workspace, root: runCacheRoot)

    #expect(selection.scope == .shared)
    #expect(selection.ignoredConfiguredScope == nil)
    #expect(caches == CacheMounts.forToolchain(.rust, scope: .shared, workspace: workspace, root: runCacheRoot))
    #expect(caches.allSatisfy { $0.hostPath.hasPrefix(runCacheRoot.path + "/shared/") })
}

@Test func repoConfiguredNarrowingIsHonouredSilently() throws {
    // cache = "workspace" asks for less, so it is kept and nothing is reported
    // as ignored — the same asymmetry as access = "minimal".
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "workspace")
    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: config)

    #expect(selection.scope == .workspace)
    #expect(selection.ignoredConfiguredScope == nil)
}

@Test func theFlagCanNarrowARepoThatAskedToShare() throws {
    let sharedConfig = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")
    let selection = try parsedRun(["--cache", "workspace"]).resolvedCacheSelection(workspaceConfig: sharedConfig)

    #expect(selection.scope == .workspace)
    #expect(selection.ignoredConfiguredScope == nil)
}

@Test func anUnusableCacheFlagIsRejectedRatherThanDefaulted() throws {
    // A typo'd --cache must not silently run with a scope the user never asked
    // for. A typo'd .spawn.toml value selects nothing, as an unknown access
    // value does, and leaves the private default in place.
    #expect(throws: ValidationError.self) {
        try parsedRun(["--cache", "everyone"]).resolvedCacheSelection(workspaceConfig: nil)
    }

    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "everyone")
    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: config)
    #expect(selection.scope == .workspace)
    #expect(selection.ignoredConfiguredScope == nil)
}

// MARK: - The caches a run actually mounts
//
// These resolve from a parsed `Spawn.Run`'s own stored properties, so a `--cache`
// or `--image` flag disconnected from cache policy fails here. They cover
// `resolvedCacheSelection` only. What the runtime is actually handed — the mounts
// in the plan, and the notices printed beside them — is covered under "Typed
// launch boundary" below, which exercises the single method `run()` calls.

@Test func aRunMountsWorkspaceScopedCachesByDefault() throws {
    let workspace = try makeTempDir(files: [:])
    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: nil)
    let caches = selection.mounts(toolchain: .rust, workspace: workspace, root: runCacheRoot)

    #expect(caches == CacheMounts.forToolchain(.rust, scope: .workspace, workspace: workspace, root: runCacheRoot))
    #expect(!caches.isEmpty)
    // Not the shared directory, whatever the workspace is called.
    #expect(!caches.contains { $0.hostPath.hasPrefix(runCacheRoot.path + "/shared/") })
}

@Test func aRunInAnotherWorkspaceMountsDifferentCaches() throws {
    let left = try makeTempDir(files: [:])
    let right = try makeTempDir(files: [:])

    let selection = try parsedRun([]).resolvedCacheSelection(workspaceConfig: nil)
    let leftCaches = selection.mounts(toolchain: .rust, workspace: left, root: runCacheRoot)
    let rightCaches = selection.mounts(toolchain: .rust, workspace: right, root: runCacheRoot)

    #expect(!leftCaches.isEmpty)
    #expect(Set(leftCaches.map(\.hostPath)).isDisjoint(with: Set(rightCaches.map(\.hostPath))))
}

@Test func aRunWithAnImageOverrideMountsNoCaches() throws {
    let workspace = try makeTempDir(files: [:])

    for scope in CacheScope.allCases {
        let run = try parsedRun(["--cache", scope.rawValue, "--image", "ghcr.io/foo/bar"])
        let selection = try run.resolvedCacheSelection(workspaceConfig: nil)
        #expect(selection.imageOverride == "ghcr.io/foo/bar")
        #expect(selection.mounts(toolchain: .rust, workspace: workspace, root: runCacheRoot).isEmpty)
    }
}

@Test func aRunWithAnUnusableCacheFlagMountsNothingAndFails() throws {
    #expect(throws: ValidationError.self) {
        try parsedRun(["--cache", "everyone"]).resolvedCacheSelection(workspaceConfig: nil)
    }
}

// MARK: - Typed launch boundary
//
// `resolvedLaunch` is the whole of what `run()` composes: it resolves the cache
// decision from the parsed command itself and returns both the plan the runtime
// receives and the notices printed beside it. There is no cache scope for `run()`
// to pass, so these tests cover the launch as the real command performs it.

@Test func parsedRunResolvesThePlanHandedToTheRuntime() throws {
    let run = try parsedRun(["--cpus", "6", "--memory", "12g"])
    let workspaceURL = try makeTempDir(files: [:])
    let cacheRoot = try makeTempDir(files: [:])
    let workspace = Mount(hostPath: workspaceURL.path, readOnly: false)
    let state = Mount(
        hostPath: "/state/codex",
        guestPath: "/home/coder/.codex",
        readOnly: false
    )
    let expectedCaches = CacheMounts.forToolchain(
        .rust,
        scope: .workspace,
        workspace: workspaceURL,
        root: cacheRoot
    )

    let launch = try run.resolvedLaunch(
        image: "spawn-rust:latest",
        resolvedMounts: [workspace, state],
        toolchain: .rust,
        workspace: workspaceURL,
        workspaceConfig: nil,
        cacheRoot: cacheRoot,
        environment: ["SPAWN_SAFE_MODE": "1"],
        entrypoint: ["cargo", "test"],
        allocateTerminal: true
    )
    let plan = launch.plan

    #expect(launch.cacheNotices.isEmpty)
    #expect(!expectedCaches.isEmpty)
    #expect(plan.image == "spawn-rust:latest")
    #expect(plan.mounts == [workspace, state] + expectedCaches)
    #expect(expectedCaches.allSatisfy { CacheMounts.directoryStatus(at: $0.hostPath) == .ready })
    #expect(plan.environment == ["SPAWN_SAFE_MODE": "1"])
    #expect(plan.workdir == workspace.guestPath)
    #expect(plan.entrypoint == ["cargo", "test"])
    #expect(plan.resources == .init(cpus: 6, memory: "12g"))
    #expect(plan.io == .init(keepStandardInputOpen: true, allocateTerminal: true))
    #expect(plan.removeOnExit)
}

@Test func parsedRunPlanPreservesSharedOptInAndCustomImageExclusion() throws {
    let workspaceURL = try makeTempDir(files: [:])
    let cacheRoot = try makeTempDir(files: [:])
    let workspace = Mount(hostPath: workspaceURL.path, readOnly: false)

    let sharedRun = try parsedRun(["--cache", "shared"])
    let sharedLaunch = try sharedRun.resolvedLaunch(
        image: "spawn-rust:latest",
        resolvedMounts: [workspace],
        toolchain: .rust,
        workspace: workspaceURL,
        workspaceConfig: nil,
        cacheRoot: cacheRoot,
        environment: [:],
        entrypoint: ["true"],
        allocateTerminal: false
    )
    let sharedCaches = CacheMounts.forToolchain(
        .rust,
        scope: .shared,
        workspace: workspaceURL,
        root: cacheRoot
    )

    let customRun = try parsedRun(["--image", "ghcr.io/example/custom:latest"])
    let customLaunch = try customRun.resolvedLaunch(
        image: "ghcr.io/example/custom:latest",
        resolvedMounts: [workspace],
        toolchain: .rust,
        workspace: workspaceURL,
        workspaceConfig: nil,
        cacheRoot: cacheRoot,
        environment: [:],
        entrypoint: ["true"],
        allocateTerminal: false
    )

    #expect(!sharedCaches.isEmpty)
    #expect(sharedLaunch.plan.mounts == [workspace] + sharedCaches)
    #expect(sharedCaches.allSatisfy { $0.hostPath.hasPrefix(cacheRoot.path + "/shared/") })
    #expect(customLaunch.plan.mounts == [workspace])
    #expect(customLaunch.cacheNotices.isEmpty)
}

@Test func aLaunchNeverWarnsAboutSharingItDidNotMountOrMountsSharingItDidNotWarnAbout() throws {
    // The invariant the launch type exists for: the notice a run prints and the
    // directories it mounts come from one decision. Asserting them together is
    // what makes a scope substituted on either side of the launch fail here
    // instead of only in the container argv.
    let workspaceURL = try makeTempDir(files: [:])
    let cacheRoot = try makeTempDir(files: [:])
    let workspace = Mount(hostPath: workspaceURL.path, readOnly: false)
    let hostileConfig = WorkspaceConfig(
        toolchainName: nil,
        agentName: nil,
        accessName: nil,
        cacheName: "shared"
    )
    let cases: [(arguments: [String], config: WorkspaceConfig?, sharing: Bool)] = [
        ([], nil, false),
        ([], hostileConfig, false),
        (["--cache", "workspace"], hostileConfig, false),
        (["--cache", "shared"], nil, true),
        (["--cache", "shared"], hostileConfig, true),
    ]

    for testCase in cases {
        let launch = try parsedRun(testCase.arguments).resolvedLaunch(
            image: "spawn-rust:latest",
            resolvedMounts: [workspace],
            toolchain: .rust,
            workspace: workspaceURL,
            workspaceConfig: testCase.config,
            cacheRoot: cacheRoot,
            environment: [:],
            entrypoint: ["true"],
            allocateTerminal: false
        )
        let caches = launch.plan.mounts.filter { $0.hostPath.hasPrefix(cacheRoot.path + "/") }
        let mountedShared = caches.contains { $0.hostPath.hasPrefix(cacheRoot.path + "/shared/") }
        let warnedAboutSharing = launch.cacheNotices.contains { $0.contains("readable and writable") }

        #expect(!caches.isEmpty)
        #expect(mountedShared == testCase.sharing)
        #expect(warnedAboutSharing == testCase.sharing)
        // A repo asking to share is refused, and the refusal is reported by the
        // same value that mounted the private caches.
        let refusedRepoSharing = launch.cacheNotices.contains {
            $0.hasPrefix("Warning: ignoring .spawn.toml cache=shared.")
        }
        #expect(refusedRepoSharing == (testCase.config != nil && testCase.arguments.isEmpty))
    }
}

// MARK: - What a run tells the user about its cache scope

@Test func aSharedRunSaysTheCacheIsSharedAndAnOrdinaryRunSaysNothing() {
    #expect(RunLaunchSummary.cacheNotices(scope: .workspace, ignoredConfiguredScope: nil).isEmpty)

    let shared = RunLaunchSummary.cacheNotices(scope: .shared, ignoredConfiguredScope: nil)
    #expect(shared.count == 1)
    #expect(shared.allSatisfy { $0.contains("--cache shared") })
    #expect(shared.allSatisfy { $0.contains("readable and writable") })
}

@Test func aRunReportsTheRepoCacheScopeItRefused() {
    let notices = RunLaunchSummary.cacheNotices(scope: .workspace, ignoredConfiguredScope: .shared)

    #expect(notices.count == 1)
    guard let warning = notices.first else {
        Issue.record("no notice for an ignored cache scope")
        return
    }
    // Same shape as the access warning: what was ignored, and the flag that
    // would honour it.
    #expect(warning.hasPrefix("Warning: ignoring .spawn.toml cache=shared."))
    #expect(warning.contains("Pass '--cache shared' explicitly"))
}
