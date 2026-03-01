import ArgumentParser
import Foundation

extension Spawn {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build or pull base images."
        )

        @Argument(help: "Toolchain to build: base, cpp, rust, go (default: all)")
        var toolchain: String?

        @Flag(name: .long, help: "Show build commands.")
        var verbose: Bool = false

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
                let imageName = tc.imageName
                print("Building \(imageName)...")

                // Write embedded Containerfile to a temp file
                let tmpContainerfile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spawn-Containerfile-\(tc.rawValue)")
                try ContainerfileTemplates.content(for: tc)
                    .write(to: tmpContainerfile, atomically: true, encoding: .utf8)

                let status = try ContainerRunner.runRaw(
                    args: ["build", "-t", imageName, "-f", tmpContainerfile.path, "."]
                )

                try? FileManager.default.removeItem(at: tmpContainerfile)

                if status != 0 {
                    throw ExitCode(status)
                }
                print("Built \(imageName)")
            }
        }
    }
}
