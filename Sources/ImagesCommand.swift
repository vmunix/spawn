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
            guard let root = ImageChecker.defaultStoreRoot else {
                throw SpawnError.runtimeError(
                    "Unable to resolve Application Support directory.")
            }
            let statePath = root.appendingPathComponent("state.json")
            guard let data = try? Data(contentsOf: statePath) else {
                throw SpawnError.runtimeError(
                    "No image store found. Is the container system running? Try: container system start")
            }

            struct ImageEntry: Decodable {
                let mediaType: String?
                let digest: String
                let size: Int64
            }

            guard let state = try? JSONDecoder().decode([String: ImageEntry].self, from: data) else {
                throw SpawnError.runtimeError("Failed to parse image store at \(statePath.path)")
            }

            let images = state.keys.sorted().filter { all || $0.hasPrefix("spawn-") }

            if images.isEmpty {
                if all {
                    print("No images found.")
                } else {
                    print("No spawn images found. Run 'spawn build' to create them.")
                }
                return
            }

            // Header
            let nameWidth = max(images.map(\.count).max() ?? 0, 10)
            print(
                "NAME".padding(toLength: nameWidth + 2, withPad: " ", startingAt: 0)
                    + "DIGEST")
            for name in images {
                let digest = state[name]?.digest ?? "unknown"
                let shortDigest = String(digest.prefix(20)) + "..."
                print(
                    name.padding(toLength: nameWidth + 2, withPad: " ", startingAt: 0)
                        + shortDigest)
            }
        }
    }
}
