import ArgumentParser
import Foundation

extension Spawn {
    struct Image: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage spawn images.",
            subcommands: [List.self, Remove.self],
            defaultSubcommand: List.self
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List available spawn images."
            )

            @Flag(name: .long, help: "Show all images, not just spawn-* ones.")
            var all: Bool = false

            mutating func run() throws {
                if all {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                    process.arguments = ["image", "list"]
                    process.standardOutput = FileHandle.standardOutput
                    process.standardError = FileHandle.standardError
                    try process.run()
                    process.waitUntilExit()
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                process.arguments = ["image", "list"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.standardError
                try process.run()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard let output = String(data: data, encoding: .utf8) else { return }
                let lines = output.components(separatedBy: "\n")

                var found = false
                for (index, line) in lines.enumerated() {
                    if index == 0 {
                        print(line)
                        continue
                    }
                    if line.hasPrefix("spawn-") {
                        print(line)
                        found = true
                    }
                }
                if !found {
                    print("No spawn images found. Run 'spawn build' to create them.")
                }
            }
        }

        struct Remove: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "rm",
                abstract: "Remove one or more spawn images."
            )

            @Argument(help: "Image names to remove (e.g. spawn-cpp:latest).")
            var names: [String]

            mutating func run() throws {
                for name in names {
                    let status = try ContainerRunner.runRaw(args: ["image", "delete", name])
                    if status != 0 {
                        throw ExitCode(status)
                    }
                }
            }
        }
    }
}
