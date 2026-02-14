import Foundation

struct DevcontainerConfig: Sendable {
    let toolchain: Toolchain?
    let image: String?
    let dockerfile: String?
    let env: [String: String]

    /// Returns nil if the file can't be parsed
    static func parse(at url: URL) -> DevcontainerConfig? {
        guard let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let image = json["image"] as? String
        let env = json["containerEnv"] as? [String: String] ?? [:]

        // Check for build.dockerfile
        var dockerfile: String? = nil
        if let build = json["build"] as? [String: Any] {
            dockerfile = build["dockerfile"] as? String
        }

        // Determine toolchain
        let toolchain: Toolchain?
        if let image {
            toolchain = inferToolchain(from: image)
        } else if let features = json["features"] as? [String: Any] {
            toolchain = inferToolchainFromFeatures(features)
        } else if dockerfile != nil {
            toolchain = nil  // signal to build the Dockerfile
        } else {
            toolchain = .base
        }

        return DevcontainerConfig(
            toolchain: toolchain,
            image: image,
            dockerfile: dockerfile,
            env: env
        )
    }

    private static func inferToolchain(from image: String) -> Toolchain {
        let lower = image.lowercased()
        if lower.contains("rust") { return .rust }
        if lower.contains("go") || lower.contains("golang") { return .go }
        if lower.contains("cpp") || lower.contains("c++") { return .cpp }
        return .base
    }

    private static func inferToolchainFromFeatures(_ features: [String: Any]) -> Toolchain {
        for key in features.keys {
            let lower = key.lowercased()
            if lower.contains("rust") { return .rust }
            if lower.contains("go") || lower.contains("golang") { return .go }
            if lower.contains("cpp") || lower.contains("c++") { return .cpp }
        }
        return .base
    }
}
