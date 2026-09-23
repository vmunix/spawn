import ArgumentParser
import Foundation

extension Spawn {
    struct Cache: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage spawn-owned caches.",
            discussion: """
                Build caches and native backend artifacts are separate. Use
                `spawn doctor` to see the native artifact locations and sizes.
                """,
            subcommands: [Clean.self]
        )

        struct Clean: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Reclaim the current experimental native backend cache.",
                discussion: """
                    Example:
                      spawn cache clean --native
                      spawn cache clean --native --dry-run

                    Removes the current Containerization-versioned image, initfs,
                    and rootfs cache. The next native launch rebuilds it. This
                    does not remove workspace build caches or older native cache
                    layouts. Cleanup refuses to run while a native launch is active.
                    """
            )

            @Flag(name: .long, help: "Confirm removal of the current native backend cache.")
            var native: Bool = false

            @Flag(name: .long, help: "Show what would be reclaimed without removing it.")
            var dryRun: Bool = false

            static func clean(stateDir: URL, dryRun: Bool = false) throws -> UInt64 {
                try NativeCacheStore(
                    stateRoot: stateDir.appendingPathComponent("native-runtime")
                ).cleanCurrent(dryRun: dryRun)
            }

            mutating func run() throws {
                guard native else {
                    throw ValidationError("Specify '--native' to clean the experimental native backend cache.")
                }
                let allocatedBytes = try Self.clean(stateDir: Paths.stateDir, dryRun: dryRun)
                let formatted = ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: allocatedBytes),
                    countStyle: .file
                )
                if dryRun {
                    print("Would remove the current native cache (about \(formatted) allocated); no files were deleted.")
                } else {
                    print("Removed the current native cache (about \(formatted) allocated); the next native launch will rebuild it.")
                }
            }
        }
    }
}
