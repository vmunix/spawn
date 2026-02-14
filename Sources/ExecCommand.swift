import ArgumentParser
import Foundation

extension CCC {
    struct Exec: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a command in a running container."
        )

        @Argument(help: "Container ID.")
        var id: String

        @Argument(parsing: .captureForPassthrough, help: "Command to execute.")
        var command: [String]

        mutating func run() throws {
            var args = ["exec", id]
            args += command
            let status = try ContainerRunner.runRaw(args: args)
            throw ExitCode(status)
        }
    }
}
