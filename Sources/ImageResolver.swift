import ContainerizationOCI

enum ImageResolver {
    static func resolve(toolchain: Toolchain, imageOverride: String?) throws -> String {
        let name = imageOverride ?? "spawn-\(toolchain.rawValue):latest"
        // Validate the image reference is well-formed OCI
        let _ = try Reference.parse(name)
        return name
    }
}
