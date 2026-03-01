import ArgumentParser
import Foundation

extension Spawn {
    struct Image: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage spawn images.",
            subcommands: [List.self, Remove.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List available spawn images."
            )

            @Flag(name: .long, help: "Show all images, not just spawn-* ones.")
            var all: Bool = false

            mutating func run() throws {
                if all {
                    let status = try ContainerRunner.runRaw(args: ["image", "list"])
                    if status != 0 {
                        throw ExitCode(status)
                    }
                    return
                }

                let (status, output) = try ContainerRunner.runCapture(args: ["image", "list"])
                if status != 0 {
                    throw ExitCode(status)
                }

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

            /// Validate an image name for safe removal. Returns nil if valid,
            /// or an error message if the name should be rejected.
            static func validateRemoval(_ name: String) -> String? {
                guard name.hasPrefix("spawn-") else {
                    return "Refusing to remove '\(name)': only spawn-* images can be removed."
                }
                // Warn against removing base since other images depend on it
                if name == "spawn-base:latest" || name == "spawn-base" {
                    return "Refusing to remove '\(name)': other spawn images depend on it. Remove dependent images first."
                }
                return nil
            }

            mutating func run() throws {
                // Validate all names before removing any
                for name in names {
                    if let error = Self.validateRemoval(name) {
                        throw ValidationError(error)
                    }
                }

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
