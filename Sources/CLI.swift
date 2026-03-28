import ArgumentParser

@main
struct Spawn: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spawn",
        abstract: "Sandboxed AI coding agents on macOS.",
        discussion: """
            Quick start:
              spawn build              Build container images (required once)
              spawn .                  Run Claude Code in the current directory
              spawn . codex            Run Codex instead
              spawn doctor             Check images, config, and workspace detection

            Common workflows:
              spawn shell <id>         Open a shell in a running container
              spawn exec <id> -- ls    Run a one-off command in a running container
              spawn image list         Show locally built spawn images

            Common run options:
              --yolo                   Skip permission gates (default: safe mode)
              --no-git                 Don't mount git/SSH config into container
              --shell                  Drop into a shell instead of running an agent
              --toolchain <name>       Override auto-detected toolchain (base/cpp/rust/go)
            """,
        version: "0.1.2",
        subcommands: [Run.self, Build.self, Image.self, List.self, Stop.self, Exec.self, Shell.self, Doctor.self],
        defaultSubcommand: Run.self
    )
}
