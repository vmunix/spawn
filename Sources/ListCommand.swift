import ArgumentParser
import Foundation

extension Spawn {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List running containers."
        )

        mutating func run() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
            process.arguments = ["list"]
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
        }
    }
}
