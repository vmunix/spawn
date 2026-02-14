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
                guard let tc = Toolchain(rawValue: name) else {
                    throw ValidationError("Unknown toolchain: \(name). Use: base, cpp, rust, go.")
                }
                toolchains = [tc]
            } else {
                // base must be built first since other images depend on it
                toolchains = [.base] + Toolchain.allCases.filter { $0 != .base }
            }

            for tc in toolchains {
                print("Building spawn-\(tc.rawValue)...")
                let imageName = "spawn-\(tc.rawValue):latest"

                // Write embedded Containerfile to a temp file
                let tmpContainerfile = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spawn-Containerfile-\(tc.rawValue)")
                try ContainerfileTemplates.content(for: tc)
                    .write(to: tmpContainerfile, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                process.arguments = ["build", "-t", imageName, "-f", tmpContainerfile.path, "."]
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()

                try? FileManager.default.removeItem(at: tmpContainerfile)

                if process.terminationStatus != 0 {
                    throw ExitCode(process.terminationStatus)
                }
                print("Built \(imageName)")
            }
        }
    }
}
