import ArgumentParser
import Foundation

extension Spawn {
    struct Build: ParsableCommand {
        struct BuildWorkspace: Sendable, Equatable {
            let imageName: String
            let contextURL: URL
            let containerfileURL: URL
        }

        static let configuration = CommandConfiguration(
            abstract: "Build spawn-managed base and toolchain images.",
            discussion: """
                Examples:
                  spawn build
                  spawn build rust
                  spawn build js
                  spawn build base --memory 16g

                Omit the toolchain to build all spawn-managed images. `spawn-base` is
                always built first.

                This command does not build workspace Dockerfile/devcontainer images.
                Use `spawn --runtime workspace-image` to build those on demand.
                """
        )

        @Argument(help: "Toolchain to build: base, cpp, rust, go, js. Omit to build all.")
        var toolchain: String?

        @Option(name: .long, help: "CPU cores for the builder container.")
        var cpus: Int = 4

        @Option(name: .long, help: "Builder container memory (e.g., 8g).")
        var memory: String = "8g"

        @Flag(name: .long, help: "Show build commands.")
        var verbose: Bool = false

        static func prepareBuildWorkspace(
            for toolchain: Toolchain,
            temporaryDirectory: URL = FileManager.default.temporaryDirectory
        ) throws -> BuildWorkspace {
            let directoryName = "spawn-build-\(toolchain.rawValue)-\(UUID().uuidString)"
            let contextURL = temporaryDirectory.appendingPathComponent(directoryName)
            try FileManager.default.createDirectory(at: contextURL, withIntermediateDirectories: true)

            let containerfileURL = contextURL.appendingPathComponent("Containerfile")
            try ContainerfileTemplates.content(for: toolchain)
                .write(to: containerfileURL, atomically: true, encoding: .utf8)

            return BuildWorkspace(
                imageName: toolchain.imageName,
                contextURL: contextURL,
                containerfileURL: containerfileURL
            )
        }

        static func buildArgs(
            imageName: String,
            containerfileURL: URL,
            contextURL: URL,
            cpus: Int,
            memory: String
        ) -> [String] {
            [
                "build",
                "-c", "\(cpus)",
                "-m", memory,
                "-t", imageName,
                "-f", containerfileURL.path,
                contextURL.path,
            ]
        }

        mutating func run() throws {
            if verbose { logger.logLevel = .debug }

            try ContainerRunner.preflight()

            let toolchains: [Toolchain]
            if let name = toolchain {
                toolchains = [try Toolchain.parse(name)]
            } else {
                // base must be built first since other images depend on it
                toolchains = [.base] + Toolchain.allCases.filter { $0 != .base }
            }

            for tc in toolchains {
                let buildWorkspace = try Self.prepareBuildWorkspace(for: tc)
                print("Building \(buildWorkspace.imageName)...")

                let status = try ContainerRunner.runRaw(
                    args: Self.buildArgs(
                        imageName: buildWorkspace.imageName,
                        containerfileURL: buildWorkspace.containerfileURL,
                        contextURL: buildWorkspace.contextURL,
                        cpus: cpus,
                        memory: memory
                    )
                )

                try? FileManager.default.removeItem(at: buildWorkspace.contextURL)

                if status != 0 {
                    throw ExitCode(status)
                }
                print("Built \(buildWorkspace.imageName)")
            }
        }
    }
}
