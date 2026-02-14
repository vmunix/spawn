import ArgumentParser
import Foundation

@main
struct CCC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ccc",
        abstract: "Sandboxed AI coding agents on macOS.",
        version: "0.1.0",
        subcommands: [Run.self],
        defaultSubcommand: Run.self
    )
}
