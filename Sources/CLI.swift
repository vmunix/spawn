import ArgumentParser
import Foundation

@main
struct Spawn: AsyncParsableCommand {
    private static let directSubcommands: Set<String> = [
        "run",
        "build",
        "image",
        "list",
        "stop",
        "exec",
        "shell",
        "doctor",
        "help",
    ]

    private static let rootOnlyFlags: Set<String> = [
        "-h",
        "--help",
        "--version",
    ]

    static let configuration = CommandConfiguration(
        commandName: "spawn",
        abstract: "Workspace-first agent and command containers on macOS.",
        discussion: """
            Quick start:
              spawn                    Run the default agent in the current directory
              spawn codex              Run Codex instead
              spawn -- cargo test      Run a command in the workspace container
              spawn --shell            Open a shell in the workspace container
              spawn -C ~/code/project  Run in another workspace
              spawn doctor             Check runtime readiness, images, config, and workspace detection
              spawn doctor --json      Machine-readable diagnostics

            Runtime selection:
              --runtime auto            Default; refuse to guess Dockerfile runtimes
              --runtime spawn           Use spawn-managed images
              --runtime workspace-image Use a workspace Dockerfile/devcontainer build
              --rebuild-workspace-image Force a rebuild for workspace-image runs

            Workspace defaults:
              .spawn.toml [workspace]   Default agent; access still requires --access
              .spawn.toml [toolchain]   Default spawn-managed toolchain base

            Operational commands:
              spawn build              Build spawn-managed images
              spawn image list         Show locally built spawn-managed images
              spawn list               List running containers
              spawn exec <id> -- ls    Run a one-off command in a running container
              spawn shell <id>         Open a shell in a running container
              spawn stop <id>          Stop a running container

            Common run options:
              --yolo                   Skip permission gates (default: safe mode)
              --access <name>          Host access profile (minimal/git/trusted)
              --shell                  Drop into a shell instead of running an agent
              --toolchain <name>       Override toolchain (base/cpp/rust/go/js)

            Bare invocations and run-style options route to `spawn run`.
            Use `spawn -- <command...>` for passthrough workspace commands.
            Use `spawn help run` for launch options.
            """,
        version: "0.2.1",
        subcommands: [Run.self, Build.self, Image.self, List.self, Stop.self, Exec.self, Shell.self, Doctor.self]
    )

    static func rewrittenArguments(_ arguments: [String]) -> [String] {
        guard let first = arguments.first else {
            return ["run"]
        }

        if directSubcommands.contains(first) {
            return arguments
        }

        if rootOnlyFlags.contains(first) {
            return arguments
        }

        if AgentProfile.named(first) != nil {
            return ["run", "--agent", first] + arguments.dropFirst()
        }

        if first == "--" || first.hasPrefix("-") {
            return ["run"] + arguments
        }

        return arguments
    }

    static func rootRoutingError(
        for arguments: [String],
        fileManager: FileManager = .default
    ) -> ValidationError? {
        guard let first = arguments.first else {
            return nil
        }

        if directSubcommands.contains(first) || rootOnlyFlags.contains(first) || AgentProfile.named(first) != nil {
            return nil
        }

        if first == "--" || first.hasPrefix("-") {
            return nil
        }

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: first, isDirectory: &isDirectory), isDirectory.boolValue {
            return ValidationError("Workspace paths are selected with -C/--cwd. Example: spawn -C \(first)")
        }

        return ValidationError(
            "Unknown subcommand or agent: \(first). Use 'spawn -- <command...>' for workspace commands, or 'spawn help' to list subcommands."
        )
    }

    static func main(_ arguments: [String]?) async {
        let providedArguments = arguments ?? Array(CommandLine.arguments.dropFirst())
        if let error = rootRoutingError(for: providedArguments) {
            exit(withError: error)
        }
        let rewrittenArguments = rewrittenArguments(providedArguments)

        do {
            var command = try parseAsRoot(rewrittenArguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    static func main() async {
        await main(nil)
    }
}
