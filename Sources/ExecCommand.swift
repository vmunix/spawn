import ArgumentParser
import Foundation

extension Spawn {
    struct Exec: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a command in a running container.",
            discussion: """
                Examples:
                  spawn exec 3f2b8d4f -- ls -la /workspace
                  spawn exec 3f2b8d4f -- /bin/bash

                Use `spawn shell <id>` as a shortcut for opening `/bin/bash`.
                """
        )

        @Argument(help: "Container ID.")
        var id: String

        @Argument(parsing: .captureForPassthrough, help: "Command to execute.")
        var command: [String]

        mutating func run() throws {
            var args = ["exec", id]
            args += command
            let status = try ContainerRunner.runRaw(args: args)
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}
