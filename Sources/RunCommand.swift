import ArgumentParser
import Foundation

extension Spawn {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run an AI coding agent in a sandboxed container."
        )

        @Argument(
            help: "Directory to mount as workspace.",
            transform: { URL(fileURLWithPath: $0).standardizedFileURL }
        )
        var path: URL

        @Argument(help: "Agent: claude-code (default), codex")
        var agent: String = "claude-code"

        @Option(name: .long, help: "Additional directory to mount (repeatable).")
        var mount: [String] = []

        @Option(name: .customLong("read-only"), help: "Mount directory read-only (repeatable).")
        var readOnlyMounts: [String] = []

        @Option(name: .long, help: "Environment variable KEY=VALUE (repeatable).")
        var env: [String] = []

        @Option(name: .customLong("env-file"), help: "Path to env file.")
        var envFile: String?

        @Option(name: .long, help: "Override base image.")
        var image: String?

        @Option(name: .long, help: "Override toolchain: base, cpp, rust, go")
        var toolchain: String?

        @Option(name: .long, help: "CPU cores.")
        var cpus: Int = 4

        @Option(name: .long, help: "Memory (e.g., 8g).")
        var memory: String = "8g"

        @Flag(name: .long, help: "Drop into shell instead of running agent.")
        var shell: Bool = false

        @Flag(name: .customLong("no-git"), help: "Don't mount ~/.gitconfig or SSH.")
        var noGit: Bool = false

        @Flag(name: .long, help: "Show container commands.")
        var verbose: Bool = false

        @Flag(name: .long, help: "Full auto mode — skip all permission gates.")
        var yolo: Bool = false

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
            let resolvedToolchain: Toolchain
            if let override = toolchain {
                resolvedToolchain = try Toolchain.parse(override)
            } else {
                resolvedToolchain = ToolchainDetector.detect(in: path) ?? .base
            }

            // Tell the user what we detected
            if toolchain == nil {
                print("Detected toolchain: \(resolvedToolchain.rawValue)")
            }

            // Print permission mode
            if yolo {
                print("Yolo mode: all operations unrestricted")
            } else {
                print("Safe mode: remote git operations require approval (use --yolo to disable)")
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
