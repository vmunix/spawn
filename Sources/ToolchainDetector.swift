import Foundation

/// Priority-ordered toolchain detection from project files and configuration.
enum ToolchainDetector: Sendable {
    enum Source: Sendable, Equatable {
        case spawnToml
        case devcontainer
        case devcontainerDockerfile
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
            case .devcontainerDockerfile:
                ".devcontainer/devcontainer.json (build.dockerfile)"
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
    /// `toolchain == nil` means the workspace defines its own runtime and `spawn`
    /// should require explicit runtime selection instead of silently guessing.
    static func inspect(in directory: URL) -> Inspection {
        let fm = FileManager.default

        // Priority 1: .spawn.toml
        if let config = loadWorkspaceConfig(in: directory), let toolchain = config.toolchain {
            return Inspection(toolchain: toolchain, source: .spawnToml)
        }

        // Priority 2: .devcontainer/devcontainer.json
        let devcontainer =
            directory
            .appendingPathComponent(".devcontainer")
            .appendingPathComponent("devcontainer.json")
        if fm.fileExists(atPath: devcontainer.path),
            let config = parseDevcontainer(at: devcontainer)
        {
            if let toolchain = config.toolchain {
                return Inspection(toolchain: toolchain, source: .devcontainer)
            }
            if config.dockerfile != nil {
                return Inspection(toolchain: nil, source: .devcontainerDockerfile)
            }
        }

        // Priority 3: Dockerfile / Containerfile
        if fm.fileExists(atPath: directory.appendingPathComponent("Dockerfile").path) || fm.fileExists(atPath: directory.appendingPathComponent("Containerfile").path) {
            return Inspection(toolchain: nil, source: .dockerfile)
        }

        // Priority 4: Auto-detect from repo files
        return autoDetect(in: directory)
    }

    /// Returns nil when the workspace defines its own runtime.
    /// Returns a Toolchain when a spawn-* image variant should be used.
    static func detect(in directory: URL) -> Toolchain? {
        inspect(in: directory).toolchain
    }

    /// Loads `.spawn.toml` workspace defaults when present.
    static func loadWorkspaceConfig(in directory: URL) -> WorkspaceConfig? {
        let spawnToml = directory.appendingPathComponent(".spawn.toml")
        guard FileManager.default.fileExists(atPath: spawnToml.path) else { return nil }
        return parseSpawnToml(at: spawnToml)
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

    private static func parseSpawnToml(at url: URL) -> WorkspaceConfig? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var section: String?
        var toolchainName: String?
        var agentName: String?
        var accessName: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Track TOML sections
            if trimmed.hasPrefix("[") {
                section =
                    if trimmed.hasPrefix("[toolchain]") {
                        "toolchain"
                    } else if trimmed.hasPrefix("[workspace]") {
                        "workspace"
                    } else {
                        nil
                    }
                continue
            }

            guard let section else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            switch (section, key) {
            case ("toolchain", "base"):
                toolchainName = value
            case ("workspace", "agent"):
                agentName = value
            case ("workspace", "access"):
                accessName = value
            default:
                continue
            }
        }

        return WorkspaceConfig(
            toolchainName: toolchainName,
            agentName: agentName,
            accessName: accessName
        )
    }

    private static func parseDevcontainer(at url: URL) -> DevcontainerConfig? {
        DevcontainerConfig.parse(at: url)
    }
}
