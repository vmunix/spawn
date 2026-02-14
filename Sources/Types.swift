import Foundation

/// Supported language toolchains, each corresponding to a container image variant.
enum Toolchain: String, CaseIterable, Sendable {
    case base
    case cpp
    case rust
    case go
}

/// A host-to-guest filesystem mount for the container.
struct Mount: Sendable {
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

    var name: String {
        URL(fileURLWithPath: hostPath).standardizedFileURL.lastPathComponent
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
