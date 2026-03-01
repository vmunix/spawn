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

            Common options (pass to 'spawn run'):
              --yolo                   Skip permission gates (default: safe mode)
              --no-git                 Don't mount git/SSH config into container
              --shell                  Drop into a shell instead of running an agent
              --toolchain <name>       Override auto-detected toolchain (base/cpp/rust/go)
            """,
        version: "0.1.2",
        subcommands: [Run.self, Build.self, Image.self, List.self, Stop.self, Exec.self],
        defaultSubcommand: Run.self
    )
}
