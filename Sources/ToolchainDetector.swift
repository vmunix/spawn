import Foundation

/// Priority-ordered toolchain detection from project files and configuration.
enum ToolchainDetector: Sendable {
    enum Source: Sendable, Equatable {
        case spawnToml
        case devcontainer
        case dockerfile
        case cargo
        case goMod
        case cmake
        case bunLock
        case denoConfig
        case denoLock
        case pnpmLock
        case yarnLock
        case packageLock
        case packageJSON
        case fallback

        var detail: String {
            switch self {
            case .spawnToml:
                ".spawn.toml"
            case .devcontainer:
                ".devcontainer/devcontainer.json"
            case .dockerfile:
                "workspace has Dockerfile/Containerfile"
            case .cargo:
                "auto-detected from Cargo.toml/rust-toolchain.toml"
            case .goMod:
                "auto-detected from go.mod/go.sum"
            case .cmake:
                "auto-detected from CMakeLists.txt"
            case .bunLock:
                "auto-detected from bun.lock/bun.lockb"
            case .denoConfig:
                "auto-detected from deno.json/deno.jsonc"
            case .denoLock:
                "auto-detected from deno.lock"
            case .pnpmLock:
                "auto-detected from pnpm-lock.yaml"
            case .yarnLock:
                "auto-detected from yarn.lock"
            case .packageLock:
                "auto-detected from package-lock.json/npm-shrinkwrap.json"
            case .packageJSON:
                "auto-detected from package.json"
            case .fallback:
                "fallback"
            }
        }
    }

    struct Inspection: Sendable, Equatable {
        let toolchain: Toolchain?
        let source: Source
    }

    /// Returns the resolved toolchain plus the source that drove the decision.
    /// `toolchain == nil` means a Dockerfile/Containerfile was found.
    static func inspect(in directory: URL) -> Inspection {
        let fm = FileManager.default

        // Priority 1: .spawn.toml
        let spawnToml = directory.appendingPathComponent(".spawn.toml")
        if fm.fileExists(atPath: spawnToml.path),
            let toolchain = parseSpawnToml(at: spawnToml)
        {
            return Inspection(toolchain: toolchain, source: .spawnToml)
        }

        // Priority 2: .devcontainer/devcontainer.json
        let devcontainer =
            directory
            .appendingPathComponent(".devcontainer")
            .appendingPathComponent("devcontainer.json")
        if fm.fileExists(atPath: devcontainer.path),
            let toolchain = parseDevcontainer(at: devcontainer)
        {
            return Inspection(toolchain: toolchain, source: .devcontainer)
        }

        // Priority 3: Dockerfile / Containerfile
        if fm.fileExists(atPath: directory.appendingPathComponent("Dockerfile").path) || fm.fileExists(atPath: directory.appendingPathComponent("Containerfile").path) {
            return Inspection(toolchain: nil, source: .dockerfile)
        }

        // Priority 4: Auto-detect from repo files
        return autoDetect(in: directory)
    }

    /// Returns nil when a Dockerfile/Containerfile is found (caller should build it directly).
    /// Returns a Toolchain when a spawn-* image variant should be used.
    static func detect(in directory: URL) -> Toolchain? {
        inspect(in: directory).toolchain
    }

    private static func autoDetect(in directory: URL) -> Inspection {
        let fm = FileManager.default
        let exists = { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }

        if exists("Cargo.toml") || exists("rust-toolchain.toml") {
            return Inspection(toolchain: .rust, source: .cargo)
        }
        if exists("go.mod") || exists("go.sum") {
            return Inspection(toolchain: .go, source: .goMod)
        }
        if exists("CMakeLists.txt") {
            return Inspection(toolchain: .cpp, source: .cmake)
        }
        if exists("bun.lock") || exists("bun.lockb") {
            return Inspection(toolchain: .js, source: .bunLock)
        }
        if exists("deno.json") || exists("deno.jsonc") {
            return Inspection(toolchain: .js, source: .denoConfig)
        }
        if exists("deno.lock") {
            return Inspection(toolchain: .js, source: .denoLock)
        }
        if exists("pnpm-lock.yaml") {
            return Inspection(toolchain: .js, source: .pnpmLock)
        }
        if exists("yarn.lock") {
            return Inspection(toolchain: .js, source: .yarnLock)
        }
        if exists("package-lock.json") || exists("npm-shrinkwrap.json") {
            return Inspection(toolchain: .js, source: .packageLock)
        }
        if exists("package.json") {
            return Inspection(toolchain: .js, source: .packageJSON)
        }

        return Inspection(toolchain: .base, source: .fallback)
    }

    private static func parseSpawnToml(at url: URL) -> Toolchain? {
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
                let value =
                    trimmed
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
