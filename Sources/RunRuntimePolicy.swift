import ArgumentParser

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
    /// beats the private-by-default `workspace` scope.
    ///
    /// Unlike `access`, a repo-configured value is honoured rather than
    /// downgraded: sharing a cache exposes only build artifacts fetched from
    /// public registries — or, at worst, dependencies of the very repo that
    /// asked to share — never host credentials. It is still announced, because
    /// a shared cache is writable by every other workspace using it.
    static func effectiveCacheScopeName(
        cacheOverride: String?,
        workspaceConfig: WorkspaceConfig?
    ) -> String {
        if let cacheOverride {
            return cacheOverride
        }

        if let configured = workspaceConfig?.cacheName {
            return configured
        }

        return CacheScope.workspace.rawValue
    }
}
