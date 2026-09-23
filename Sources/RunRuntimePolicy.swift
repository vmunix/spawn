import ArgumentParser
import Foundation

/// Centralizes runtime and access rules for workspace launches.
enum RunRuntimePolicy: Sendable {
    /// The cache decision for one launch, resolved before any container work.
    ///
    /// Keeping the image override in the decision makes "custom images get no
    /// caches" part of the same value as the scope and warning. Callers cannot
    /// report one policy and later construct mounts from a second set of raw
    /// CLI/config inputs.
    struct CacheSelection: Sendable, Equatable {
        let scope: CacheScope
        let ignoredConfiguredScope: CacheScope?
        let imageOverride: String?

        func mounts(
            toolchain: Toolchain,
            workspace: URL,
            root: URL = CacheMounts.root()
        ) -> [Mount] {
            CacheMounts.forRun(
                toolchain: toolchain,
                imageOverride: imageOverride,
                scope: scope,
                workspace: workspace,
                root: root
            )
        }
    }

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

    /// Resolves all cache policy for a run from its CLI and repository inputs.
    ///
    /// Repo-controlled config never widens exposure, the same rule `access`
    /// follows. `shared` reaches into caches other workspaces wrote and lets
    /// this one rewrite what they build against next — the cross-workspace
    /// channel scoping exists to close — so only an explicit `--cache shared`
    /// may select it. A repo asking for `workspace` is a narrowing and is
    /// honoured silently; a repo asking for anything else is ignored and
    /// reported in the returned selection.
    static func resolveCacheSelection(
        cacheOverride: String?,
        imageOverride: String?,
        workspaceConfig: WorkspaceConfig?
    ) throws -> CacheSelection {
        if let cacheOverride {
            return CacheSelection(
                scope: try CacheScope.parse(cacheOverride),
                ignoredConfiguredScope: nil,
                imageOverride: imageOverride
            )
        }

        let selection = defaultCacheSelection(workspaceConfig: workspaceConfig)
        return CacheSelection(
            scope: selection.scope,
            ignoredConfiguredScope: selection.ignoredConfiguredScope,
            imageOverride: imageOverride
        )
    }

    /// The selection doctor reports for a run without CLI overrides.
    ///
    /// An unparseable value is not reported: it selected nothing, exactly as an
    /// unparseable `access` value does.
    static func defaultCacheSelection(
        workspaceConfig: WorkspaceConfig?
    ) -> CacheSelection {
        let configured = workspaceConfig?.cacheScope
        return CacheSelection(
            scope: .workspace,
            ignoredConfiguredScope: configured.flatMap { $0 == .workspace ? nil : $0 },
            imageOverride: nil
        )
    }
}
