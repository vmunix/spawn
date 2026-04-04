import ArgumentParser

@main
struct Spawn: AsyncParsableCommand {
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
              spawn doctor             Check images, config, and workspace detection
              spawn doctor --json      Machine-readable diagnostics

            Runtime selection:
              --runtime auto            Default; refuse to guess Dockerfile runtimes
              --runtime spawn           Use spawn-managed images
              --runtime workspace-image Use a workspace Dockerfile/devcontainer build
              --rebuild-workspace-image Force a rebuild for workspace-image runs

            Workspace defaults:
              .spawn.toml [workspace]   Default agent and access profile
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

            Bare invocations route to `spawn run`. Use `spawn help run` for launch options.
            """,
        version: "0.2.0",
        subcommands: [Run.self, Build.self, Image.self, List.self, Stop.self, Exec.self, Shell.self, Doctor.self],
        defaultSubcommand: Run.self
    )
}
