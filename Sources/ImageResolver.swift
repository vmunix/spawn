import Foundation

/// Maps a toolchain to its container image name, with optional override and OCI validation.
enum ImageResolver: Sendable {
    /// Validates a reference matches the OCI image name format: [domain/]path[:tag][@sha256:digest].
    private static func isValidReference(_ name: String) -> Bool {
        let domain = "(?:[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?(?::[0-9]+)?/)?"
        let path = "(?:[a-z0-9]+(?:[._/-][a-z0-9]+)*)"
        let tag = "(?::[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127})?"
        let digest = "(?:@sha256:[0-9a-fA-F]{64})?"
        let pattern = "^\(domain)\(path)\(tag)\(digest)$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// Returns the image reference for the given toolchain, or validates and returns the override.
    /// Throws if the reference is not a well-formed OCI image name.
    static func resolve(toolchain: Toolchain, imageOverride: String?) throws -> String {
        let name = imageOverride ?? toolchain.imageName
        // Reject bare 64-char hex strings (ambiguous with content digests)
        let isBareHex = name.count == 64 && name.allSatisfy { $0.isHexDigit }
        guard !isBareHex, name.count <= 255, isValidReference(name) else {
            throw SpawnError.runtimeError("Invalid OCI image reference: \(name)")
        }
        return name
    }
}
