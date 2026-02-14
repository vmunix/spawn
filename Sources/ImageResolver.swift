enum ImageResolver {
    static func resolve(toolchain: Toolchain, imageOverride: String?) -> String {
        if let override = imageOverride { return override }
        return "ccc-\(toolchain.rawValue):latest"
    }
}
