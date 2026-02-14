import ContainerizationOCI

/// Maps a toolchain to its container image name, with optional override and OCI validation.
enum ImageResolver: Sendable {
    /// Returns the image reference for the given toolchain, or validates and returns the override.
    /// Throws if the reference is not a well-formed OCI image name.
    static func resolve(toolchain: Toolchain, imageOverride: String?) throws -> String {
        let name = imageOverride ?? "spawn-\(toolchain.rawValue):latest"
        // Validate the image reference is well-formed OCI
        let _ = try Reference.parse(name)
        return name
    }
}
