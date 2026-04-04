import ArgumentParser
import Foundation

/// Resolves workspace-first launch inputs into a concrete workspace and agent.
struct RunLaunchRequest: Sendable, Equatable {
    let workspace: URL
    let agent: String
    let workspaceConfig: WorkspaceConfig?
}

enum RunLaunchResolver: Sendable {
    static func resolve(
        agent: String?,
        cwdOverride: String?,
        currentDirectory: URL
    ) throws -> RunLaunchRequest {
        if let cwdOverride {
            try validateDirectory(at: cwdOverride, label: "Workspace path")
        }

        let workspace = URL(fileURLWithPath: cwdOverride ?? currentDirectory.path).standardizedFileURL
        let workspaceConfig = ToolchainDetector.loadWorkspaceConfig(in: workspace)
        let resolvedAgent = agent ?? workspaceConfig?.agentName ?? AgentProfile.claudeCode.name

        if AgentProfile.named(resolvedAgent) == nil {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedAgent, isDirectory: &isDirectory), isDirectory.boolValue {
                throw ValidationError("Workspace paths are selected with -C/--cwd. Example: spawn -C \(resolvedAgent)")
            }

            throw ValidationError("Unknown agent: \(resolvedAgent). Use 'claude-code' or 'codex'.")
        }

        return RunLaunchRequest(
            workspace: workspace,
            agent: resolvedAgent,
            workspaceConfig: workspaceConfig
        )
    }

    private static func validateDirectory(at path: String, label: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            throw ValidationError("\(label) does not exist: \(path)")
        }
        guard isDir.boolValue else {
            throw ValidationError("\(label) is not a directory: \(path)")
        }
    }
}
