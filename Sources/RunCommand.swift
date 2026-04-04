import ArgumentParser
import Foundation

extension Spawn {
    struct Run: AsyncParsableCommand {
        struct LaunchRequest: Sendable, Equatable {
            let workspace: URL
            let agent: String
            let workspaceConfig: WorkspaceConfig?
        }

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

                Workspace defaults:
                  .spawn.toml [workspace]        Default agent and access profile
                  .spawn.toml [toolchain]        Default spawn-managed toolchain base

                Other useful forms:
                  spawn --toolchain js           Force the JS/TS spawn image
                  spawn --yolo                   Disable safe-mode prompts

                Safe mode is the default. It keeps local coding workflows smooth while
                gating remote-write git and gh operations inside the container.
                """
        )

        @Argument(help: "Agent to run: claude-code, codex.")
        var agent: String?

        @Argument(parsing: .captureForPassthrough, help: "Command to run inside the workspace container after '--'.")
        var command: [String] = []

        @Option(name: [.short, .long], help: "Directory to mount as workspace (default: current directory).")
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

        @Option(name: .long, help: "Runtime mode: auto, spawn, workspace-image.")
        var runtime: String = RuntimeMode.auto.rawValue

        @Flag(name: .long, help: "Force a rebuild when using '--runtime workspace-image'.")
        var rebuildWorkspaceImage: Bool = false

        @Flag(name: .long, help: "Show container commands.")
        var verbose: Bool = false

        @Flag(name: .long, help: "Skip permission gates (default: safe mode, prompts before git push).")
        var yolo: Bool = false

        private static func sessionDescription(shell: Bool, command: [String]) -> String {
            if shell {
                return "shell (/bin/bash)"
            }

            if !command.isEmpty {
                return "command (\(command.joined(separator: " ")))"
            }

            return "agent entrypoint"
        }

        static func launchSummaryLines(
            workspace: URL,
            agent: String,
            shell: Bool,
            command: [String],
            yolo: Bool,
            runtimeMode: RuntimeMode,
            toolchainWasOverridden: Bool,
            detection: ToolchainDetector.Inspection,
            resolvedToolchain: Toolchain,
            image: String,
            accessProfile: AccessProfile,
            extraMountCount: Int,
            readOnlyMountCount: Int,
            envCount: Int,
            cpus: Int,
            memory: String
        ) -> [String] {
            let toolchainDetail: String
            if runtimeMode == .workspaceImage, detection.toolchain == nil, !toolchainWasOverridden {
                toolchainDetail = "workspace-image (\(detection.source.detail))"
            } else if toolchainWasOverridden {
                toolchainDetail = "\(resolvedToolchain.rawValue) (--toolchain override)"
            } else {
                toolchainDetail = "\(resolvedToolchain.rawValue) (\(detection.source.detail))"
            }

            return [
                "Launch summary:",
                "  workspace: \(workspace.path)",
                "  agent: \(agent)",
                "  session: \(sessionDescription(shell: shell, command: command))",
                yolo ? "  mode: yolo" : "  mode: safe",
                "  runtime: \(runtimeMode.rawValue)",
                "  access: \(accessProfile.rawValue)",
                "  toolchain: \(toolchainDetail)",
                "  image: \(image)",
                "  extra mounts: \(extraMountCount) read-write, \(readOnlyMountCount) read-only",
                "  environment: \(envCount) variable\(envCount == 1 ? "" : "s")",
                "  resources: \(cpus) CPU, \(memory) memory",
            ]
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

        static func validateRuntimeOptions(
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

        static func resolveLaunchRequest(
            agent: String?,
            cwdOverride: String?,
            currentDirectory: URL
        ) throws -> LaunchRequest {
            if let cwdOverride {
                try validateDirectory(at: cwdOverride, label: "Workspace path")
            }

            let workspace = URL(fileURLWithPath: cwdOverride ?? currentDirectory.path).standardizedFileURL
            let workspaceConfig = ToolchainDetector.loadWorkspaceConfig(in: workspace)
            let resolvedAgent = agent ?? workspaceConfig?.agentName ?? AgentProfile.claudeCode.name

            if AgentProfile.named(resolvedAgent) == nil {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: resolvedAgent, isDirectory: &isDirectory), isDirectory.boolValue {
                    throw ValidationError("Workspace paths are selected with -C/--cwd. Example: spawn -C \(resolvedAgent)")
                }

                throw ValidationError("Unknown agent: \(resolvedAgent). Use 'claude-code' or 'codex'.")
            }

            return LaunchRequest(
                workspace: workspace,
                agent: resolvedAgent,
                workspaceConfig: workspaceConfig
            )
        }

        mutating func run() async throws {
            if verbose { logger.logLevel = .debug }

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
            let resolvedAccess = access ?? workspaceConfig?.accessName ?? AccessProfile.minimal.rawValue
            let accessProfile = try AccessProfile.parse(resolvedAccess)
            let runtimeMode = try RuntimeMode.parse(runtime)
            try Self.validateRuntimeOptions(
                runtimeMode: runtimeMode,
                image: image,
                toolchain: toolchain,
                rebuildWorkspaceImage: rebuildWorkspaceImage
            )

            // Resolve toolchain
            let detection = ToolchainDetector.inspect(in: path)
            if runtimeMode == .auto, Self.requiresExplicitRuntimeSelection(for: detection.source) {
                throw Self.runtimeSelectionError(for: detection.source)
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
            } else if let override = toolchain {
                workspaceImagePlan = nil
                resolvedToolchain = try Toolchain.parse(override)
                resolvedImage = try ImageResolver.resolve(
                    toolchain: resolvedToolchain,
                    imageOverride: image
                )
            } else {
                workspaceImagePlan = nil
                resolvedToolchain = detection.toolchain ?? .base
                resolvedImage = try ImageResolver.resolve(
                    toolchain: resolvedToolchain,
                    imageOverride: image
                )

                // Pre-flight: check if image exists locally
                if !ImageChecker.imageExists(resolvedImage) {
                    let buildHint =
                        image != nil
                        ? "Pull or build the image first."
                        : "Run 'spawn build \(resolvedToolchain.rawValue)' first."
                    throw SpawnError.imageNotFound(image: resolvedImage, hint: buildHint)
                }

                // Warn if toolchain image is older than spawn-base:latest
                if image == nil, resolvedToolchain != .base,
                    ImageChecker.isStale(resolvedImage)
                {
                    print("Warning: \(resolvedImage) was built before spawn-base:latest.")
                    print("Run 'spawn build \(resolvedToolchain.rawValue)' to rebuild.")
                }
            }

            // Seed Claude Code safe-mode permissions
            if !yolo, command.isEmpty, !shell, agent == "claude-code" {
                let claudeSettingsDir = Paths.stateDir.appendingPathComponent(agent)
                    .appendingPathComponent("claude")
                SettingsSeeder.seed(settingsDir: claudeSettingsDir)
            }

            // Resolve mounts
            let resolvedMounts = MountResolver.resolve(
                target: path,
                additional: mount,
                readOnly: readOnlyMounts,
                access: accessProfile,
                agent: agent
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

            // Working directory — derived from the primary mount's guest path
            let workdir = resolvedMounts[0].guestPath

            let summaryLines = Self.launchSummaryLines(
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
            let status = try ContainerRunner.run(
                image: resolvedImage,
                mounts: resolvedMounts,
                env: environment,
                workdir: workdir,
                entrypoint: entrypoint,
                cpus: cpus,
                memory: memory
            )

            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}
