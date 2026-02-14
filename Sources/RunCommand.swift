import ArgumentParser
import Foundation

extension CCC {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run an AI coding agent in a sandboxed container."
        )

        @Argument(help: "Directory to mount as workspace.",
                  transform: { str in URL(fileURLWithPath: str).standardizedFileURL })
        var path: URL

        @Argument(help: "Agent to run: claude-code (default), codex")
        var agent: String = "claude-code"

        mutating func run() async throws {
            print("Would run \(agent) on \(path.path)")
        }
    }
}
