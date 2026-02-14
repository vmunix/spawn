import Foundation

/// Loads and parses KEY=VALUE environment files (comments, quotes supported).
enum EnvLoader: Sendable {
    /// Load environment variables from a file at the given path.
    static func load(from path: String) throws -> [String: String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return parse(content)
    }

    /// Load from the default config location (`$XDG_CONFIG_HOME/spawn/env`).
    static func loadDefault() -> [String: String] {
        let defaultPath = Paths.configDir.appendingPathComponent("env").path
        return (try? load(from: defaultPath)) ?? [:]
    }

    /// Parse KEY=VALUE content, stripping comments and surrounding quotes.
    static func parse(_ content: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eqIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            env[key] = value
        }
        return env
    }

    /// Returns the names of any required keys missing from `env`.
    static func validateRequired(_ required: [String], in env: [String: String]) -> [String] {
        required.filter { env[$0] == nil }
    }
}
