enum ImageResolver {
    static func resolve(toolchain: Toolchain, imageOverride: String?) -> String {
        if let override = imageOverride { return override }
        return "spawn-\(toolchain.rawValue):latest"
    }
}
