import ArgumentParser
import Foundation

extension CCC {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build or pull base images."
        )

        @Argument(help: "Toolchain to build: base, cpp, rust, go (default: all)")
        var toolchain: String?

        @Flag(name: .long, help: "Show build commands.")
        var verbose: Bool = false

        mutating func run() throws {
            let toolchains: [Toolchain]
            if let name = toolchain {
                guard let tc = Toolchain(rawValue: name) else {
                    throw ValidationError("Unknown toolchain: \(name). Use: base, cpp, rust, go.")
                }
                toolchains = [tc]
            } else {
                toolchains = Toolchain.allCases
            }

            for tc in toolchains {
                print("Building ccc-\(tc.rawValue)...")
                let imageName = "ccc-\(tc.rawValue):latest"
                let containerfilePath = "Images/\(tc.rawValue)/Containerfile"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                process.arguments = ["build", "-t", imageName, "-f", containerfilePath, "."]
                process.standardOutput = verbose ? FileHandle.standardOutput : nil
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    throw ExitCode(process.terminationStatus)
                }
                print("Built \(imageName)")
            }
        }
    }
}
