import ArgumentParser
import Foundation

extension Spawn {
    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop a running container.",
            discussion: """
                Example:
                  spawn stop 3f2b8d4f

                Use a container ID from `spawn list`.
                """
        )

        @Argument(help: "Container ID to stop.")
        var id: String

        mutating func run() throws {
            let status = try ContainerRunner.runRaw(args: ["stop", id])
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}
