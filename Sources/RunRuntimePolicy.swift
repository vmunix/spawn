import ArgumentParser
import Foundation

/// Centralizes runtime and access rules for workspace launches.
enum RunRuntimePolicy: Sendable {
    static func requiresExplicitRuntimeSelection(for source: ToolchainDetector.Source) -> Bool {
        switch source {
        case .dockerfile, .devcontainerDockerfile:
            true
        case .spawnToml, .devcontainer, .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
            false
        }
    }

    static func runtimeSelectionError(for source: ToolchainDetector.Source) -> SpawnError {
        switch source {
        case .dockerfile:
            return .runtimeError(
                "This workspace defines a Dockerfile/Containerfile. Pass '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            )
        case .devcontainerDockerfile:
            return .runtimeError(
                "This workspace uses .devcontainer/devcontainer.json with build.dockerfile. Pass '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            )
        case .spawnToml, .devcontainer, .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
            return .runtimeError("Runtime selection error")
        }
    }

    static func validateOptions(
        runtimeMode: RuntimeMode,
        image: String?,
        toolchain: String?,
        rebuildWorkspaceImage: Bool
    ) throws {
        if rebuildWorkspaceImage, runtimeMode != .workspaceImage {
            throw ValidationError("'--rebuild-workspace-image' requires '--runtime workspace-image'.")
        }
        if runtimeMode == .workspaceImage, toolchain != nil {
            throw ValidationError("Use either '--runtime workspace-image' or '--toolchain', not both.")
        }
        if runtimeMode == .workspaceImage, image != nil {
            throw ValidationError("Use either '--runtime workspace-image' or '--image', not both.")
        }
    }

    static func effectiveAccessName(
        accessOverride: String?,
        workspaceConfig: WorkspaceConfig?
    ) -> String {
        if let accessOverride {
            return accessOverride
        }

        if workspaceConfig?.accessProfile == .minimal {
            return AccessProfile.minimal.rawValue
        }

        return AccessProfile.minimal.rawValue
    }

    /// Resolves the cache scope for a run: `--cache` beats `.spawn.toml`, which
    /// may only narrow.
    ///
    /// Repo-controlled config never widens exposure, the same rule `access`
    /// follows. `shared` reaches into caches other workspaces wrote and lets
    /// this one rewrite what they build against next — the cross-workspace
    /// channel scoping exists to close — so only an explicit `--cache shared`
    /// may select it. A repo asking for `workspace` is a narrowing and is
    /// honoured silently; a repo asking for anything else is ignored, and
    /// `ignoredConfiguredCacheScope` reports that so the user can be told.
    static func effectiveCacheScopeName(
        cacheOverride: String?,
        workspaceConfig: WorkspaceConfig?
    ) -> String {
        if let cacheOverride {
            return cacheOverride
        }

        if workspaceConfig?.cacheScope == .workspace {
            return CacheScope.workspace.rawValue
        }

        return CacheScope.workspace.rawValue
    }

    /// The wider cache scope a workspace asked for in `.spawn.toml` and did not
    /// get, or `nil` when nothing was ignored.
    ///
    /// An unparseable value is not reported: it selected nothing, exactly as an
    /// unparseable `access` value does.
    static func ignoredConfiguredCacheScope(
        cacheOverride: String?,
        workspaceConfig: WorkspaceConfig?
    ) -> CacheScope? {
        guard cacheOverride == nil,
            let configured = workspaceConfig?.cacheScope,
            configured != .workspace
        else {
            return nil
        }
        return configured
    }

    /// Every cache volume a run should mount, derived from the raw run inputs.
    ///
    /// `run()` used to resolve the scope and pass it to `CacheVolumes` at the
    /// call site, which left the most security-critical argument in the program
    /// — the scope a run actually mounts with — reachable only by launching a
    /// container. Deriving it in one pure function puts it under unit test; the
    /// launch path then has no cache decision of its own to get wrong.
    static func cacheVolumes(
        cacheOverride: String?,
        workspaceConfig: WorkspaceConfig?,
        toolchain: Toolchain,
        imageOverride: String?,
        workspace: URL
    ) throws -> [CacheVolume] {
        let scope = try CacheScope.parse(
            effectiveCacheScopeName(cacheOverride: cacheOverride, workspaceConfig: workspaceConfig)
        )
        return CacheVolumes.forRun(
            toolchain: toolchain,
            imageOverride: imageOverride,
            scope: scope,
            workspace: workspace
        )
    }
}
