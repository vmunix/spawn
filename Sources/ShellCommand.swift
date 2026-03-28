import ArgumentParser
import Foundation

extension Spawn {
    struct Shell: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Open a shell in a running container.",
            discussion: """
                Example:
                  spawn shell 3f2b8d4f

                This is a shortcut for `spawn exec <id> -- /bin/bash`.
                """
        )

        @Argument(help: "Container ID.")
        var id: String

        mutating func run() throws {
            let status = try ContainerRunner.runRaw(args: ["exec", id, "/bin/bash"])
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}
