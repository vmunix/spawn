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

@Test func defaultKernelPathUsesHostContainerArchitectureSuffix() {
    let path = Spawn.Doctor.defaultKernelPath(appRoot: "/Users/me/Library/Application Support/com.apple.container")
    #expect(path.hasSuffix("kernels/default.kernel-\(Spawn.Doctor.hostContainerArchitecture)"))
}

@Test func defaultKernelCheckReportsInstalledKernel() throws {
    let appRoot = try makeTempDir(files: [
        "kernels/default.kernel-arm64": "kernel"
    ])

    let check = Spawn.Doctor.defaultKernelCheck(
        systemStatus: Spawn.Doctor.SystemStatus(status: "running", appRoot: appRoot.path),
        containerArchitecture: "arm64"
    )

    #expect(check.status == .ok)
    #expect(check.title == "Default kernel")
    #expect(check.detail == appRoot.appendingPathComponent("kernels/default.kernel-arm64").path)
}

@Test func defaultKernelCheckReportsMissingKernel() throws {
    let appRoot = try makeTempDir(files: [:])

    let check = Spawn.Doctor.defaultKernelCheck(
        systemStatus: Spawn.Doctor.SystemStatus(status: "running", appRoot: appRoot.path),
        containerArchitecture: "arm64"
    )

    #expect(check.status == .warning)
    #expect(check.title == "Default kernel")
    #expect(check.detail.contains("container system kernel set --recommended"))
}

@Test func rosettaCheckReportsInstalledOnAppleSilicon() {
    let check = Spawn.Doctor.rosettaCheck(
        requiresRosetta: true,
        commandRunner: { executableURL, arguments in
            #expect(executableURL.path == "/usr/sbin/pkgutil")
            #expect(arguments == ["--pkg-info", "com.apple.pkg.RosettaUpdateAuto"])
            return (0, "installed")
        }
    )

    #expect(check.status == .ok)
    #expect(check.title == "Rosetta")
    #expect(check.detail == "installed")
}

@Test func rosettaCheckReportsMissingOnAppleSilicon() {
    let check = Spawn.Doctor.rosettaCheck(
        requiresRosetta: true,
        commandRunner: { _, _ in
            (1, "No receipt for 'com.apple.pkg.RosettaUpdateAuto' found")
        }
    )

    #expect(check.status == .warning)
    #expect(check.title == "Rosetta")
    #expect(check.detail.contains("softwareupdate --install-rosetta --agree-to-license"))
}

@Test func rosettaCheckReportsNotRequiredOnNonAppleSiliconHosts() {
    let check = Spawn.Doctor.rosettaCheck(requiresRosetta: false)

    #expect(check.status == .ok)
    #expect(check.title == "Rosetta")
    #expect(check.detail == "not required on this host architecture")
}

@Test func workspaceDetailIncludesWorkspaceDefaults() {
    let detail = Spawn.Doctor.workspaceDetail(
        path: fileURL("/Users/me/code/project"),
        inspection: ToolchainDetector.Inspection(toolchain: .rust, source: .spawnToml),
        workspaceConfig: WorkspaceConfig(
            toolchainName: "rust",
            agentName: "codex",
            accessName: "git",
            cacheName: nil
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
    let workspace = try makeTempDir(files: [
        "Dockerfile": "FROM ubuntu:24.04",
        ".dockerignore": "ignored.txt\n",
    ])
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
    #expect(detail.contains(plan.dockerignore?.path ?? ""))
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
    let workspace = try makeTempDir(files: [
        "Dockerfile": "FROM ubuntu:24.04",
        ".dockerignore": "ignored.txt\n",
    ])
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
        workspaceConfig: WorkspaceConfig(toolchainName: nil, agentName: "codex", accessName: "git", cacheName: nil),
        stateDir: stateDir,
        storeRoot: storeRoot
    )

    #expect(report.source == "dockerfile")
    #expect(report.defaults == Spawn.Doctor.WorkspaceDefaultsReport(agent: "codex", access: "git"))
    #expect(report.runtime?.cacheStatus == "ready")
    #expect(report.runtime?.dockerfilePath == plan.dockerfile.path)
    #expect(report.runtime?.dockerignorePath == plan.dockerignore?.path)
    #expect(report.runtime?.cacheRecordPath == plan.cacheRecord.path)
}

/// A workspace path for cache-scope assertions. Never touched on disk: the
/// cache-path functions are pure.
private let cacheWorkspace = URL(fileURLWithPath: "/Users/me/code/project")

/// Cache root for the doctor cache checks, passed explicitly so they never
/// derive a path from the real state directory.
private let doctorCacheRoot = URL(fileURLWithPath: "/state/spawn/caches")

/// Whether a check's detail names exactly this cache directory.
///
/// Plain `contains` cannot answer that: a cache root is a prefix of every cache
/// under it, so `contains("/state/spawn/caches/shared")` is satisfied by a
/// directory merely named `shared-2`. The lookahead requires the match to end at
/// a path boundary, and still matches a directory doctor rendered as
/// `<path> (not created yet)`.
private func namesPath(_ detail: String, _ path: String) -> Bool {
    let pattern = NSRegularExpression.escapedPattern(for: path) + "(?![-/A-Za-z0-9._])"
    return detail.range(of: pattern, options: .regularExpression) != nil
}

@Test func thePathMatcherRequiresAWholeDirectory() {
    // Guards the guard: a matcher that accepted a prefix would report the shared
    // cache as "named" by any detail listing a directory beside it.
    let scoped = "rust [workspace scope]: /state/spawn/caches/project-1a2b/cargo-registry (not created yet)"
    #expect(namesPath(scoped, "/state/spawn/caches/project-1a2b/cargo-registry"))
    #expect(!namesPath(scoped, "/state/spawn/caches/project-1a2b"))
    #expect(!namesPath(scoped, "/state/spawn/caches/shared/cargo-registry"))

    let shared = "rust [shared scope]: /state/spawn/caches/shared/cargo-registry, /state/spawn/caches/shared/cargo-git"
    #expect(namesPath(shared, "/state/spawn/caches/shared/cargo-registry"))
    #expect(namesPath(shared, "/state/spawn/caches/shared/cargo-git"))
}

@Test func doctorReportsBuildCaches() {
    let caches = CacheMounts.forToolchain(.rust, scope: .shared, workspace: cacheWorkspace, root: doctorCacheRoot)
    let check = Spawn.Doctor.cacheMountCheck(
        toolchain: .rust,
        scope: .shared,
        mounts: caches,
        exists: { _ in true }
    )

    #expect(check.status == .ok)
    #expect(check.title == "Build caches")
    #expect(check.detail == "rust [shared scope]: \(caches.map(\.hostPath).joined(separator: ", "))")
}

@Test func doctorMarksBuildCachesThatDoNotExistYet() {
    let caches = CacheMounts.forToolchain(.rust, scope: .workspace, workspace: cacheWorkspace, root: doctorCacheRoot)
    let check = Spawn.Doctor.cacheMountCheck(
        toolchain: .rust,
        scope: .workspace,
        mounts: caches,
        exists: { _ in false }
    )

    #expect(check.status == .ok)
    let described = caches.map { "\($0.hostPath) (not created yet)" }.joined(separator: ", ")
    #expect(check.detail == "rust [workspace scope]: \(described)")
}

@Test func doctorMarksOnlyTheMissingBuildCache() {
    let caches = CacheMounts.forToolchain(.rust, scope: .workspace, workspace: cacheWorkspace, root: doctorCacheRoot)
    guard let present = caches.first, let missing = caches.last, caches.count == 2 else {
        Issue.record("expected rust to declare two caches")
        return
    }
    let check = Spawn.Doctor.cacheMountCheck(
        toolchain: .rust,
        scope: .workspace,
        mounts: caches,
        exists: { $0 == present.hostPath }
    )

    #expect(check.detail == "rust [workspace scope]: \(present.hostPath), \(missing.hostPath) (not created yet)")
}

@Test func doctorNamesEveryBuildCacheOfAToolchain() {
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            let caches = CacheMounts.forToolchain(
                toolchain, scope: scope, workspace: cacheWorkspace, root: doctorCacheRoot
            )
            let check = Spawn.Doctor.cacheMountCheck(
                toolchain: toolchain,
                scope: scope,
                mounts: caches,
                exists: { _ in true }
            )
            for cache in caches {
                #expect(namesPath(check.detail, cache.hostPath))
            }
        }
    }
}

@Test func doctorReportsWhereACacheIsMounted() {
    // The host path alone does not say what a run does with it. Doctor's own
    // check on a real directory is what tells the user whether it exists.
    let caches = CacheMounts.forToolchain(.js, scope: .workspace, workspace: cacheWorkspace, root: doctorCacheRoot)
    let check = Spawn.Doctor.cacheMountCheck(
        toolchain: .js,
        scope: .workspace,
        mounts: caches,
        exists: Spawn.Doctor.directoryExists
    )

    #expect(!caches.isEmpty)
    // None of these temp-free paths exist, so every one must be annotated.
    for cache in caches {
        #expect(check.detail.contains("\(cache.hostPath) (not created yet)"))
    }
}

@Test func doctorSeesACacheDirectoryThatExists() throws {
    // The other half: `directoryExists` must actually distinguish. A file is not
    // a cache directory either.
    let base = try makeTempDir(files: ["not-a-directory": "x"])
    #expect(Spawn.Doctor.directoryExists(base.path))
    #expect(!Spawn.Doctor.directoryExists(base.appendingPathComponent("not-a-directory").path))
    #expect(!Spawn.Doctor.directoryExists(base.appendingPathComponent("absent").path))
}

// MARK: - Doctor reports the caches a run would really mount

@Test func doctorNamesTheCachesTheWorkspaceWouldActuallyMount() throws {
    // The reason this check exists: doctor once named the global volumes while
    // a run mounted workspace-scoped ones, so its output was decorative. The
    // expectation is computed from the run path, not written out by hand.
    let workspace = try makeTempDir(files: ["Cargo.toml": "[package]\nname = \"x\"\n"])
    let expected = CacheMounts.forRun(
        toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspace, root: doctorCacheRoot
    )

    let check = Spawn.Doctor.cacheCheck(
        workspace: workspace,
        toolchain: .rust,
        workspaceConfig: nil,
        root: doctorCacheRoot,
        exists: { _ in true }
    )

    #expect(!expected.isEmpty)
    for cache in expected {
        #expect(namesPath(check.detail, cache.hostPath))
    }
    // And it must not advertise a cache this workspace never touches.
    for shared in CacheMounts.forToolchain(.rust, scope: .shared, workspace: workspace, root: doctorCacheRoot) {
        #expect(!namesPath(check.detail, shared.hostPath))
    }
}

@Test func doctorReportsThePrivateCachesWhenARepoAsksToShare() throws {
    // A run without `--cache shared` uses the private caches whatever the repo
    // asked for, so doctor must name those — and say the request was ignored,
    // or the two would disagree about what happens next.
    let workspace = try makeTempDir(files: [:])
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "shared")

    let check = Spawn.Doctor.cacheCheck(
        workspace: workspace,
        toolchain: .rust,
        workspaceConfig: config,
        root: doctorCacheRoot,
        exists: { _ in true }
    )

    let mounted = CacheMounts.forRun(
        toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspace, root: doctorCacheRoot
    )
    #expect(!mounted.isEmpty)
    for cache in mounted {
        #expect(namesPath(check.detail, cache.hostPath))
    }
    for cache in CacheMounts.forToolchain(.rust, scope: .shared, workspace: workspace, root: doctorCacheRoot) {
        #expect(!namesPath(check.detail, cache.hostPath))
    }
    #expect(check.detail.contains("cache=shared ignored"))
    #expect(check.detail.contains("--cache shared"))
}

@Test func doctorSaysNothingAboutAnHonouredCacheScope() throws {
    let workspace = try makeTempDir(files: [:])
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "workspace")

    let check = Spawn.Doctor.cacheCheck(
        workspace: workspace,
        toolchain: .rust,
        workspaceConfig: config,
        root: doctorCacheRoot,
        exists: { _ in true }
    )
    let unset = Spawn.Doctor.cacheCheck(
        workspace: workspace,
        toolchain: .rust,
        workspaceConfig: nil,
        root: doctorCacheRoot,
        exists: { _ in true }
    )

    #expect(check.detail == unset.detail)
    #expect(!check.detail.contains("ignored"))
}

@Test func doctorIgnoresAnUnusableConfiguredCacheScope() throws {
    // An unparseable value selects nothing, exactly as an unknown access value
    // does, and leaves the private default in place.
    let workspace = try makeTempDir(files: [:])
    let config = WorkspaceConfig(toolchainName: nil, agentName: nil, accessName: nil, cacheName: "everyone")

    let check = Spawn.Doctor.cacheCheck(
        workspace: workspace,
        toolchain: .rust,
        workspaceConfig: config,
        root: doctorCacheRoot,
        exists: { _ in true }
    )

    #expect(check.status == .ok)
    let expected = CacheMounts.forRun(
        toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspace, root: doctorCacheRoot
    )
    #expect(!expected.isEmpty)
    for cache in expected {
        #expect(namesPath(check.detail, cache.hostPath))
    }
}

@Test func doctorReportsNoBuildCachesForBase() {
    let check = Spawn.Doctor.cacheMountCheck(
        toolchain: .base,
        scope: .workspace,
        mounts: [],
        exists: { _ in false }
    )

    #expect(check.status == .ok)
    #expect(check.detail == "base: none needed")
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
                dockerignorePath: "/tmp/project/.dockerignore",
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
    #expect(runtime["dockerignorePath"] as? String == "/tmp/project/.dockerignore")
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
