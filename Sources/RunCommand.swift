import ArgumentParser
import Foundation

extension Spawn {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run an AI coding agent in a sandboxed container.",
            discussion: """
                Examples:
                  spawn .                         Run Claude Code in the current directory
                  spawn . codex                   Run Codex instead
                  spawn ~/code/project --shell    Open a shell in the workspace container
                  spawn . --toolchain rust        Override auto-detection
                  spawn . --yolo                  Disable safe-mode prompts

                Safe mode is the default. It keeps local coding workflows smooth while
                gating remote-write git and gh operations inside the container.
                """
        )

        @Argument(
            help: "Directory to mount as workspace (e.g., '.').",
            transform: { URL(fileURLWithPath: $0).standardizedFileURL }
        )
        var path: URL

        @Argument(help: "Agent to run: claude-code, codex.")
        var agent: String = "claude-code"

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

        @Option(name: .long, help: "Override auto-detected toolchain: base, cpp, rust, go.")
        var toolchain: String?

        @Option(name: .long, help: "CPU cores for the container.")
        var cpus: Int = 4

        @Option(name: .long, help: "Container memory (e.g., 8g).")
        var memory: String = "8g"

        @Flag(name: .long, help: "Drop into shell instead of running agent.")
        var shell: Bool = false

        @Flag(name: .customLong("no-git"), help: "Don't mount ~/.gitconfig or SSH.")
        var noGit: Bool = false

        @Flag(name: .long, help: "Show container commands.")
        var verbose: Bool = false

        @Flag(name: .long, help: "Skip permission gates (default: safe mode, prompts before git push).")
        var yolo: Bool = false

        static func launchSummaryLines(
            workspace: URL,
            agent: String,
            shell: Bool,
            yolo: Bool,
            toolchainWasOverridden: Bool,
            detection: ToolchainDetector.Inspection,
            resolvedToolchain: Toolchain,
            image: String,
            noGit: Bool,
            extraMountCount: Int,
            readOnlyMountCount: Int,
            envCount: Int,
            cpus: Int,
            memory: String
        ) -> [String] {
            let toolchainDetail: String
            if toolchainWasOverridden {
                toolchainDetail = "\(resolvedToolchain.rawValue) (--toolchain override)"
            } else {
                toolchainDetail =
                    switch detection.source {
                    case .spawnToml:
                        "\(resolvedToolchain.rawValue) (.spawn.toml)"
                    case .devcontainer:
                        "\(resolvedToolchain.rawValue) (.devcontainer/devcontainer.json)"
                    case .dockerfile:
                        "\(resolvedToolchain.rawValue) (workspace has Dockerfile/Containerfile)"
                    case .cargo, .goMod, .cmake:
                        "\(resolvedToolchain.rawValue) (auto-detected)"
                    case .fallback:
                        "\(resolvedToolchain.rawValue) (fallback)"
                    }
            }

            return [
                "Launch summary:",
                "  workspace: \(workspace.path)",
                "  agent: \(agent)",
                shell ? "  session: shell (/bin/bash)" : "  session: agent entrypoint",
                yolo ? "  mode: yolo" : "  mode: safe",
                "  toolchain: \(toolchainDetail)",
                "  image: \(image)",
                noGit ? "  git/ssh: disabled" : "  git/ssh: mounted",
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

        mutating func run() async throws {
            if verbose { logger.logLevel = .debug }

            // Validate workspace path
            try Self.validateDirectory(at: path.path, label: "Path")

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

            // Resolve toolchain
            let detection = ToolchainDetector.inspect(in: path)
            let resolvedToolchain: Toolchain
            if let override = toolchain {
                resolvedToolchain = try Toolchain.parse(override)
            } else {
                resolvedToolchain = detection.toolchain ?? .base
            }

            // Seed Claude Code safe-mode permissions
            if !yolo, agent == "claude-code" {
                let claudeSettingsDir = Paths.stateDir.appendingPathComponent(agent)
                    .appendingPathComponent("claude")
                SettingsSeeder.seed(settingsDir: claudeSettingsDir)
            }

            // Resolve image
            let resolvedImage = try ImageResolver.resolve(
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

            // Resolve mounts
            let resolvedMounts = MountResolver.resolve(
                target: path,
                additional: mount,
                readOnly: readOnlyMounts,
                includeGit: !noGit,
                agent: agent
            )

            // Load environment
            var environment: [String: String]
            if let envFile {
                environment = try EnvLoader.load(from: envFile)
            } else {
                environment = EnvLoader.loadDefault()
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
            let entrypoint = shell ? ["/bin/bash"] : (yolo ? profile.yoloEntrypoint : profile.safeEntrypoint)

            // Working directory — derived from the primary mount's guest path
            let workdir = resolvedMounts[0].guestPath

            let summaryLines = Self.launchSummaryLines(
                workspace: path,
                agent: agent,
                shell: shell,
                yolo: yolo,
                toolchainWasOverridden: toolchain != nil,
                detection: detection,
                resolvedToolchain: resolvedToolchain,
                image: resolvedImage,
                noGit: noGit,
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
