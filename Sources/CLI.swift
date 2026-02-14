import ArgumentParser

@main
struct Spawn: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spawn",
        abstract: "Sandboxed AI coding agents on macOS.",
        version: "0.1.0",
        subcommands: [Run.self, Build.self, Image.self, List.self, Stop.self, Exec.self],
        defaultSubcommand: Run.self
    )
}
