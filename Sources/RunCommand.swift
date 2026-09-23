import ArgumentParser
import Foundation

extension Spawn {
    struct Run: AsyncParsableCommand {
        typealias LaunchRequest = RunLaunchRequest

        static let configuration = CommandConfiguration(
            abstract: "Run an agent, shell, or arbitrary command in a workspace container.",
            discussion: """
                Launch forms:
                  spawn                          Run the default agent in the current directory
                  spawn codex                    Run Codex instead
                  spawn -C ~/code/project        Run in another workspace
                  spawn -- cargo test            Run a command in the workspace container
                  spawn --shell                  Open a shell in the workspace container

                Access profiles:
                  --access minimal               Workspace and agent state only
                  --access git                   Add git identity and gh auth
                  --access trusted               Also expose copied SSH material

                Runtime modes:
                  --runtime auto                 Default; refuse to guess Dockerfile runtimes
                  --runtime spawn                Use spawn-managed image selection
                  --runtime workspace-image      Build or reuse a workspace runtime
                  --rebuild-workspace-image      Ignore cache for workspace-image runs

                Launch backends:
                  --backend cli                  Default; launch through Apple's container CLI
                  --backend native-experimental  Launch through Apple's Containerization library

                Build caches:
                  --cache workspace              Default; caches private to this workspace
                  --cache shared                 Reuse one cache across every opted-in workspace (flag only)

                Workspace defaults:
                  .spawn.toml [workspace]        Default agent; access and cache sharing require flags
                  .spawn.toml [toolchain]        Default spawn-managed toolchain base

                Other useful forms:
                  spawn --toolchain js           Force the JS/TS spawn image
                  spawn --yolo                   Disable safe-mode prompts

                Safe mode is the default. It keeps local coding workflows smooth while
                gating remote-write git and gh operations inside the container.
                """
        )

        @Option(name: .long, help: "Agent to run: claude-code, codex.")
        var agent: String?

        @Argument(parsing: .captureForPassthrough, help: "Command to run inside the workspace container after '--'.")
        var command: [String] = []

        @Option(name: [.customShort("C"), .long], help: "Directory to mount as workspace (default: current directory).")
        var cwd: String?

        @Option(name: .long, help: "Additional directory to mount (repeatable).")
        var mount: [String] = []

        @Option(name: .customLong("read-only"), help: "Mount directory read-only (repeatable).")
        var readOnlyMounts: [String] = []

        @Option(name: .long, help: "Environment variable KEY=VALUE (repeatable).")
        var env: [String] = []

        @Option(name: .customLong("env-file"), help: "Path to env file.")
        var envFile: String?

        @Option(name: .long, help: "Override auto-selected container image.")
        var image: String?

        @Option(name: .long, help: "Override auto-detected toolchain: base, cpp, rust, go, js.")
        var toolchain: String?

        @Option(name: .long, help: "CPU cores for the container.")
        var cpus: Int = 4

        @Option(name: .long, help: "Container memory (e.g., 8g).")
        var memory: String = "8g"

        @Flag(name: .long, help: "Drop into shell instead of running agent.")
        var shell: Bool = false

        @Option(name: .long, help: "Host access profile: minimal, git, trusted.")
        var access: String?

        @Option(name: .long, help: "Build cache scope: workspace (default, private), shared.")
        var cache: String?

        @Option(name: .long, help: "Runtime mode: auto, spawn, workspace-image.")
        var runtime: String = RuntimeMode.auto.rawValue

        @Option(name: .long, help: "Launch backend: cli (default), native-experimental.")
        var backend: String = ContainerBackend.cli.rawValue

        @Flag(name: .long, help: "Force a rebuild when using '--runtime workspace-image'.")
        var rebuildWorkspaceImage: Bool = false

        @Flag(name: .long, help: "Show container commands.")
        var verbose: Bool = false

        @Flag(name: .long, help: "Skip permission gates (default: safe mode, prompts before git push).")
        var yolo: Bool = false

        static func normalizedCommand(_ command: [String]) -> [String] {
            if command.first == "--" {
                return Array(command.dropFirst())
            }
            return command
        }

        private static func validateDirectory(at path: String, label: String) throws {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                throw ValidationError("\(label) does not exist: \(path)")
            }
            guard isDir.boolValue else {
                throw ValidationError("\(label) is not a directory: \(path)")
            }
        }

        static func resolveLaunchRequest(
            agent: String?,
            cwdOverride: String?,
            currentDirectory: URL
        ) throws -> LaunchRequest {
            try RunLaunchResolver.resolve(
                agent: agent,
                cwdOverride: cwdOverride,
                currentDirectory: currentDirectory
            )
        }

        /// Resolves cache policy from this parsed command's actual flags.
        /// Tests call this boundary on a parsed `Spawn.Run`, so disconnecting
        /// either `--cache` or `--image` from the launch fails without starting
        /// a container.
        func resolvedCacheSelection(
            workspaceConfig: WorkspaceConfig?
        ) throws -> RunRuntimePolicy.CacheSelection {
            try RunRuntimePolicy.resolveCacheSelection(
                cacheOverride: cache,
                imageOverride: image,
                workspaceConfig: workspaceConfig
            )
        }

        /// Freeze this parsed command's final backend-neutral launch inputs,
        /// together with what it must tell the user about its build caches.
        ///
        /// The cache decision is resolved here rather than accepted as an
        /// argument: `run()` has no cache scope to pass, so it cannot hand the
        /// runtime a scope other than the one whose notices it prints. The plan's
        /// cache mounts and the returned notices come from one `CacheSelection`
        /// derived from this command's own `--cache` and `--image`.
        ///
        /// `workspaceConfig` feeds only the "this repo asked to share and was
        /// refused" notice. Repository configuration can never widen the scope —
        /// `resolveCacheSelection` discards anything but a narrowing — so it
        /// cannot move the mounted directories, whatever is passed here.
        func resolvedLaunch(
            image: String,
            resolvedMounts: [Mount],
            toolchain: Toolchain,
            workspace: URL,
            workspaceConfig: WorkspaceConfig?,
            cacheRoot: URL = CacheMounts.root(),
            environment: [String: String],
            entrypoint: [String],
            allocateTerminal: Bool = isatty(STDIN_FILENO) != 0
        ) throws -> ResolvedLaunch {
            let cacheSelection = try resolvedCacheSelection(workspaceConfig: workspaceConfig)
            let preparedCacheMounts = CacheMounts.prepare(
                cacheSelection.mounts(
                    toolchain: toolchain,
                    workspace: workspace,
                    root: cacheRoot
                )
            )

            let plan = try ResolvedLaunchPlan.workspace(
                image: image,
                resolvedMounts: resolvedMounts,
                preparedCacheMounts: preparedCacheMounts,
                environment: environment,
                entrypoint: entrypoint,
                cpus: cpus,
                memory: memory,
                allocateTerminal: allocateTerminal
            )

            return ResolvedLaunch(
                plan: plan,
                cacheNotices: RunLaunchSummary.cacheNotices(
                    scope: cacheSelection.scope,
                    ignoredConfiguredScope: cacheSelection.ignoredConfiguredScope
                )
            )
        }

        /// The single handoff from command orchestration to container execution.
        /// Keeping status translation here makes every runtime obey the same CLI
        /// exit behavior.
        func executeLaunch(
            _ launch: ResolvedLaunch,
            using containerRuntime: any ContainerRuntime
        ) async throws {
            let status = try await containerRuntime.launch(launch.plan)
            if status != 0 {
                throw ExitCode(status)
            }
        }

        mutating func run() async throws {
            try await run(using: ProductionContainerRuntimeFactory())
        }

        /// Execute through a fixed runtime. Tests use this convenience to prove
        /// the fully resolved launch crosses the semantic boundary unchanged.
        mutating func run(
            using containerRuntime: any ContainerRuntime,
            imageStoreRoot: URL? = nil,
            stateDir: URL = Paths.stateDir
        ) async throws {
            try await run(
                using: FixedContainerRuntimeFactory(runtime: containerRuntime),
                imageStoreRoot: imageStoreRoot,
                stateDir: stateDir
            )
        }

        /// Execute through an injected factory so tests cover the real parsed
        /// backend selector rather than merely testing the enum in isolation.
        mutating func run(
            using runtimeFactory: any ContainerRuntimeFactory,
            imageStoreRoot: URL? = nil,
            stateDir: URL = Paths.stateDir
        ) async throws {
            if verbose { logger.logLevel = .debug }
            command = Self.normalizedCommand(command)

            if shell, !command.isEmpty {
                throw ValidationError("Use either --shell or '-- <command...>', not both.")
            }

            let launchRequest = try Self.resolveLaunchRequest(
                agent: agent,
                cwdOverride: cwd,
                currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
            )
            let path = launchRequest.workspace
            let agent = launchRequest.agent
            let workspaceConfig = launchRequest.workspaceConfig

            // Validate workspace path
            try Self.validateDirectory(at: path.path, label: "Workspace path")

            // Validate additional mount paths
            for mountPath in mount {
                try Self.validateDirectory(at: mountPath, label: "Mount path")
            }

            // Validate read-only mount paths
            for roPath in readOnlyMounts {
                try Self.validateDirectory(at: roPath, label: "Read-only mount path")
            }

            // Resolve agent profile
            guard let profile = AgentProfile.named(agent) else {
                throw ValidationError("Unknown agent: \(agent). Use 'claude-code' or 'codex'.")
            }
            let resolvedAccess = RunRuntimePolicy.effectiveAccessName(
                accessOverride: access,
                workspaceConfig: workspaceConfig
            )
            let accessProfile = try AccessProfile.parse(resolvedAccess)
            if access == nil, let configuredAccess = workspaceConfig?.accessProfile, configuredAccess != .minimal {
                print("Warning: ignoring .spawn.toml access=\(configuredAccess.rawValue). Pass '--access \(configuredAccess.rawValue)' explicitly to opt into host auth exposure.")
            }
            // Reject a bad '--cache' before any container work. The resolved
            // value is deliberately discarded: `resolvedLaunch` below derives it
            // again from these same flags so that the mounts and the notices
            // cannot come from different decisions, and by then a workspace image
            // may already have been built.
            _ = try resolvedCacheSelection(workspaceConfig: workspaceConfig)
            let selectedBackend = try ContainerBackend.parse(backend)
            let runtimeMode = try RuntimeMode.parse(runtime)
            try RunRuntimePolicy.validateOptions(
                runtimeMode: runtimeMode,
                image: image,
                toolchain: toolchain,
                rebuildWorkspaceImage: rebuildWorkspaceImage
            )

            // Resolve toolchain
            let detection = ToolchainDetector.inspect(in: path)
            if runtimeMode == .auto, RunRuntimePolicy.requiresExplicitRuntimeSelection(for: detection.source) {
                throw RunRuntimePolicy.runtimeSelectionError(for: detection.source)
            }
            let resolvedToolchain: Toolchain
            let resolvedImage: String
            let workspaceImagePlan: WorkspaceImageRuntime.Plan?
            if runtimeMode == .workspaceImage {
                let plan = try WorkspaceImageRuntime.plan(for: path)
                let result = try WorkspaceImageRuntime.ensureBuilt(
                    plan: plan,
                    cpus: cpus,
                    memory: memory,
                    forceRebuild: rebuildWorkspaceImage
                )
                workspaceImagePlan = result.plan
                resolvedToolchain = .base
                resolvedImage = plan.image
            } else {
                workspaceImagePlan = nil
                let managedImage = try ManagedImagePolicy.resolve(
                    detection: detection,
                    toolchainOverride: toolchain,
                    imageOverride: image,
                    storeRoot: imageStoreRoot
                )
                resolvedToolchain = managedImage.toolchain
                resolvedImage = managedImage.image
                for warning in managedImage.warnings {
                    print(warning)
                }
            }

            // Seed Claude Code safe-mode permissions
            if !yolo, command.isEmpty, !shell, agent == "claude-code" {
                let claudeSettingsDir = stateDir.appendingPathComponent(agent)
                    .appendingPathComponent("claude")
                SettingsSeeder.seed(settingsDir: claudeSettingsDir)
            }

            // Resolve mounts
            let resolvedMounts = MountResolver.resolve(
                target: path,
                additional: mount,
                readOnly: readOnlyMounts,
                access: accessProfile,
                agent: agent,
                stateDir: stateDir
            )
            // Load environment
            var environment: [String: String]
            if let envFile {
                environment = try EnvLoader.load(from: envFile)
            } else {
                environment = EnvLoader.loadDefault()
            }

            for (key, value) in workspaceImagePlan?.env ?? [:] {
                environment[key] = value
            }

            // CLI --env overrides
            for envVar in env {
                guard let parsed = EnvLoader.parseKeyValue(envVar) else {
                    throw ValidationError("Invalid env format: \(envVar). Use KEY=VALUE.")
                }
                environment[parsed.key] = parsed.value
            }

            // Safe mode: activate wrapper scripts inside the container
            if !yolo {
                environment["SPAWN_SAFE_MODE"] = "1"
            }

            // Note: we don't validate API keys here — agents support OAuth login
            // and will prompt the user to authenticate if no API key is set.
            // Credentials are persisted in $XDG_STATE_HOME/spawn/<agent>/ across runs.

            // Determine entrypoint
            let entrypoint: [String]
            if shell {
                entrypoint = ["/bin/bash"]
            } else if !command.isEmpty {
                entrypoint = command
            } else {
                entrypoint = yolo ? profile.yoloEntrypoint : profile.safeEntrypoint
            }

            let launch = try resolvedLaunch(
                image: resolvedImage,
                resolvedMounts: resolvedMounts,
                toolchain: resolvedToolchain,
                workspace: path,
                workspaceConfig: workspaceConfig,
                cacheRoot: CacheMounts.root(stateDir: stateDir),
                environment: environment,
                entrypoint: entrypoint
            )
            for notice in launch.cacheNotices {
                print(notice)
            }

            let summaryLines = RunLaunchSummary.lines(
                workspace: path,
                agent: agent,
                shell: shell,
                command: command,
                yolo: yolo,
                runtimeMode: runtimeMode,
                toolchainWasOverridden: toolchain != nil,
                detection: detection,
                resolvedToolchain: resolvedToolchain,
                image: resolvedImage,
                accessProfile: accessProfile,
                extraMountCount: mount.count,
                readOnlyMountCount: readOnlyMounts.count,
                envCount: environment.count,
                cpus: cpus,
                memory: memory
            )
            for line in summaryLines {
                print(line)
            }
            print("Launching...")
            fflush(stdout)

            // Run
            let containerRuntime = try runtimeFactory.makeRuntime(
                for: selectedBackend,
                stateDir: stateDir
            )
            try await executeLaunch(launch, using: containerRuntime)
        }
    }
}

private struct FixedContainerRuntimeFactory: ContainerRuntimeFactory {
    let runtime: any ContainerRuntime

    func makeRuntime(
        for backend: ContainerBackend,
        stateDir: URL
    ) throws -> any ContainerRuntime {
        runtime
    }
}
