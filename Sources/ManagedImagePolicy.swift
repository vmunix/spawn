import Foundation

/// Resolves and validates spawn-managed images for run launches.
enum ManagedImagePolicy: Sendable {
    struct Resolution: Sendable, Equatable {
        let toolchain: Toolchain
        let image: String
        let warnings: [String]
    }

    static func resolve(
        detection: ToolchainDetector.Inspection,
        toolchainOverride: String?,
        imageOverride: String?,
        storeRoot: URL? = nil
    ) throws -> Resolution {
        let toolchain: Toolchain
        if let toolchainOverride {
            toolchain = try Toolchain.parse(toolchainOverride)
        } else {
            toolchain = detection.toolchain ?? .base
        }

        let image = try ImageResolver.resolve(
            toolchain: toolchain,
            imageOverride: imageOverride
        )

        var warnings: [String] = []
        switch ImageChecker.imageStatus(image, storeRoot: storeRoot) {
        case .present:
            break
        case .missing:
            let buildHint =
                imageOverride != nil
                ? "Pull or build the image first."
                : "Run 'spawn build \(toolchain.rawValue)' first."
            throw SpawnError.imageNotFound(image: image, hint: buildHint)
        case .unknown:
            warnings.append("Warning: Unable to verify whether \(image) exists from the local container image store. Continuing anyway.")
        }

        if imageOverride == nil, toolchain != .base, ImageChecker.isStale(image, storeRoot: storeRoot) {
            warnings.append("Warning: \(image) was built before spawn-base:latest.")
            warnings.append("Run 'spawn build \(toolchain.rawValue)' to rebuild.")
        }

        return Resolution(
            toolchain: toolchain,
            image: image,
            warnings: warnings
        )
    }
}
