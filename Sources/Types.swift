import ArgumentParser
import Foundation

/// Launch backend selected explicitly by the user. Repository configuration
/// cannot opt into the experimental backend.
enum ContainerBackend: String, CaseIterable, Sendable {
    case cli
    case nativeExperimental = "native-experimental"

    static func parse(_ value: String) throws -> ContainerBackend {
        guard let backend = ContainerBackend(rawValue: value) else {
            throw ValidationError(
                "Unknown backend: \(value). Use 'cli' or 'native-experimental'."
            )
        }
        return backend
    }
}

/// Supported language toolchains, each corresponding to a container image variant.
enum Toolchain: String, CaseIterable, Sendable {
    case base
    case cpp
    case rust
    case go
    case js

    /// The canonical container image name for this toolchain (e.g. `spawn-rust:latest`).
    var imageName: String { "spawn-\(rawValue):latest" }

    /// Parse a toolchain name string, throwing a clear error if invalid.
    static func parse(_ name: String) throws -> Toolchain {
        guard let tc = Toolchain(rawValue: name) else {
            let valid = Toolchain.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown toolchain: \(name). Use: \(valid).")
        }
        return tc
    }
}

/// Controls which host identity and credential material is exposed inside the container.
enum AccessProfile: String, CaseIterable, Sendable {
    case minimal
    case git
    case trusted

    var mountsGitConfig: Bool {
        switch self {
        case .minimal:
            false
        case .git, .trusted:
            true
        }
    }

    var mountsGitHubCLIConfig: Bool {
        switch self {
        case .minimal:
            false
        case .git, .trusted:
            true
        }
    }

    var mountsSSHKeys: Bool {
        switch self {
        case .trusted:
            true
        case .minimal, .git:
            false
        }
    }

    /// Parse an access profile name, throwing a clear error if invalid.
    static func parse(_ name: String) throws -> AccessProfile {
        guard let profile = AccessProfile(rawValue: name) else {
            let valid = AccessProfile.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown access profile: \(name). Use: \(valid).")
        }
        return profile
    }
}

/// Controls whether build caches are private to one workspace or shared across
/// every workspace that opts in.
///
/// The default is `workspace`: a cache holds dependency sources fetched with
/// the workspace's own credentials — `cargo`'s git cache can hold private
/// repositories — and it is mounted read-write, so a shared cache is both a
/// confidentiality and an integrity channel between unrelated workspaces.
/// Sharing is therefore something a user asks for, not something they get.
enum CacheScope: String, CaseIterable, Sendable {
    /// Cache directories carry the workspace identity, so no two workspaces meet.
    case workspace
    /// One cache directory, shared by every opted-in workspace.
    case shared

    /// Parse a cache scope name, throwing a clear error if invalid.
    static func parse(_ name: String) throws -> CacheScope {
        guard let scope = CacheScope(rawValue: name) else {
            let valid = CacheScope.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown cache scope: \(name). Use: \(valid).")
        }
        return scope
    }
}

/// Parsed workspace defaults from `.spawn.toml`.
struct WorkspaceConfig: Sendable, Equatable {
    let toolchainName: String?
    let agentName: String?
    let accessName: String?
    let cacheName: String?

    var toolchain: Toolchain? {
        guard let toolchainName else { return nil }
        return Toolchain(rawValue: toolchainName)
    }

    var accessProfile: AccessProfile? {
        guard let accessName else { return nil }
        return AccessProfile(rawValue: accessName)
    }

    var cacheScope: CacheScope? {
        guard let cacheName else { return nil }
        return CacheScope(rawValue: cacheName)
    }
}

/// Controls how the runtime image is selected for a workspace.
enum RuntimeMode: String, CaseIterable, Sendable {
    case auto
    case spawn
    case workspaceImage = "workspace-image"

    static func parse(_ name: String) throws -> RuntimeMode {
        guard let mode = RuntimeMode(rawValue: name) else {
            let valid = RuntimeMode.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown runtime mode: \(name). Use: \(valid).")
        }
        return mode
    }
}

/// A host-to-guest filesystem mount for the container.
struct Mount: Sendable, Equatable {
    let hostPath: String
    let guestPath: String
    let readOnly: Bool

    /// Standard workspace mount — guest path derived from directory name
    init(hostPath: String, readOnly: Bool) {
        self.hostPath = hostPath
        self.readOnly = readOnly
        let name = URL(fileURLWithPath: hostPath).standardizedFileURL.lastPathComponent
        self.guestPath = "/workspace/\(name)"
    }

    /// Custom guest path mount (for .gitconfig, .ssh, etc.)
    init(hostPath: String, guestPath: String, readOnly: Bool) {
        self.hostPath = hostPath
        self.guestPath = guestPath
        self.readOnly = readOnly
    }
}

/// Configuration for a supported AI coding agent (entrypoint, resource defaults).
struct AgentProfile: Sendable {
    let name: String
    let safeEntrypoint: [String]
    let yoloEntrypoint: [String]
    let requiredEnvVars: [String]
    let defaultCPUs: Int
    let defaultMemory: String

    static let claudeCode = AgentProfile(
        name: "claude-code",
        safeEntrypoint: ["claude"],
        yoloEntrypoint: ["claude", "--dangerously-skip-permissions"],
        requiredEnvVars: [],
        defaultCPUs: 4,
        defaultMemory: "8g",
    )

    static let codex = AgentProfile(
        name: "codex",
        safeEntrypoint: ["codex", "--full-auto"],
        yoloEntrypoint: ["codex", "--full-auto"],
        requiredEnvVars: [],
        defaultCPUs: 4,
        defaultMemory: "8g",
    )

    static func named(_ name: String) -> AgentProfile? {
        switch name {
        case "claude-code": return .claudeCode
        case "codex": return .codex
        default: return nil
        }
    }
}
