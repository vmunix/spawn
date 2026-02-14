import ArgumentParser
import Foundation

extension Spawn {
    struct Images: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List available spawn images."
        )

        @Flag(name: .long, help: "Show all images, not just spawn-* ones.")
        var all: Bool = false

        mutating func run() throws {
            if all {
                // Pass through to container CLI directly
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                process.arguments = ["image", "list"]
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError
                try process.run()
                process.waitUntilExit()
                return
            }

            // Filter to spawn-* images: capture output, filter lines, print
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

            // Print header + spawn-* lines
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
}
