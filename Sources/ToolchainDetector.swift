import Foundation

enum ToolchainDetector {
    /// Returns nil when a Dockerfile/Containerfile is found (caller should build it directly).
    /// Returns a Toolchain when a ccc-* image variant should be used.
    static func detect(in directory: URL) -> Toolchain? {
        let fm = FileManager.default

        // Priority 1: .ccc.toml
        let cccToml = directory.appendingPathComponent(".ccc.toml")
        if fm.fileExists(atPath: cccToml.path),
           let toolchain = parseCccToml(at: cccToml) {
            return toolchain
        }

        // Priority 2: .devcontainer/devcontainer.json
        let devcontainer = directory
            .appendingPathComponent(".devcontainer")
            .appendingPathComponent("devcontainer.json")
        if fm.fileExists(atPath: devcontainer.path),
           let toolchain = parseDevcontainer(at: devcontainer) {
            return toolchain
        }

        // Priority 3: Dockerfile / Containerfile
        if fm.fileExists(atPath: directory.appendingPathComponent("Dockerfile").path) ||
           fm.fileExists(atPath: directory.appendingPathComponent("Containerfile").path) {
            return nil
        }

        // Priority 4: Auto-detect from repo files
        return autoDetect(in: directory)
    }

    private static func autoDetect(in directory: URL) -> Toolchain {
        let fm = FileManager.default
        let exists = { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }

        if exists("Cargo.toml") || exists("rust-toolchain.toml") { return .rust }
        if exists("go.mod") || exists("go.sum") { return .go }
        if exists("CMakeLists.txt") || exists("Makefile") { return .cpp }

        return .base
    }

    private static func parseCccToml(at url: URL) -> Toolchain? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inToolchainSection = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Track TOML sections
            if trimmed.hasPrefix("[") {
                inToolchainSection = trimmed.hasPrefix("[toolchain]")
                continue
            }
            guard inToolchainSection else { continue }
            // Match "base = ..." precisely
            let normalized = trimmed.replacingOccurrences(of: " ", with: "")
            if normalized.hasPrefix("base=") {
                let value = trimmed
                    .split(separator: "=", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let value, let toolchain = Toolchain(rawValue: value) {
                    return toolchain
                }
            }
        }
        return nil
    }

    private static func parseDevcontainer(at url: URL) -> Toolchain? {
        guard let config = DevcontainerConfig.parse(at: url) else { return nil }
        return config.toolchain
    }
}
