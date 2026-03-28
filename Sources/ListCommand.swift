import ArgumentParser
import Foundation

extension Spawn {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List running containers.",
            discussion: """
                Example:
                  spawn list
                """
        )

        mutating func run() throws {
            let status = try ContainerRunner.runRaw(args: ["list"])
            if status != 0 {
                throw ExitCode(status)
            }
        }
    }
}
