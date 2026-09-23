import Foundation

/// Renders the human launch summary shown before container startup.
enum RunLaunchSummary: Sendable {
    static func lines(
        workspace: URL,
        agent: String,
        shell: Bool,
        command: [String],
        yolo: Bool,
        runtimeMode: RuntimeMode,
        toolchainWasOverridden: Bool,
        detection: ToolchainDetector.Inspection,
        resolvedToolchain: Toolchain,
        image: String,
        accessProfile: AccessProfile,
        extraMountCount: Int,
        readOnlyMountCount: Int,
        envCount: Int,
        cpus: Int,
        memory: String
    ) -> [String] {
        let toolchainDetail: String
        if runtimeMode == .workspaceImage, detection.toolchain == nil, !toolchainWasOverridden {
            toolchainDetail = "workspace-image (\(detection.source.detail))"
        } else if toolchainWasOverridden {
            toolchainDetail = "\(resolvedToolchain.rawValue) (--toolchain override)"
        } else {
            toolchainDetail = "\(resolvedToolchain.rawValue) (\(detection.source.detail))"
        }

        return [
            "Launch summary:",
            "  workspace: \(workspace.path)",
            "  agent: \(agent)",
            "  session: \(sessionDescription(shell: shell, command: command))",
            yolo ? "  mode: yolo" : "  mode: safe",
            "  runtime: \(runtimeMode.rawValue)",
            "  access: \(accessProfile.rawValue)",
            "  toolchain: \(toolchainDetail)",
            "  image: \(image)",
            "  extra mounts: \(extraMountCount) read-write, \(readOnlyMountCount) read-only",
            "  environment: \(envCount) variable\(envCount == 1 ? "" : "s")",
            "  resources: \(cpus) CPU, \(memory) memory",
        ]
    }

    /// Lines a run prints about its build-cache scope, in order.
    ///
    /// Pure so the wording is under test: these two lines are the only signal a
    /// user gets that a repo asked to share caches and was refused, or that this
    /// run is writing into caches other workspaces can read.
    static func cacheNotices(scope: CacheScope, ignoredConfiguredScope: CacheScope?) -> [String] {
        var lines: [String] = []

        if let ignored = ignoredConfiguredScope {
            lines.append(
                "Warning: ignoring .spawn.toml cache=\(ignored.rawValue). Pass '--cache \(ignored.rawValue)' explicitly to opt into cross-workspace cache sharing."
            )
        }

        if scope == .shared {
            lines.append(
                "Note: build caches are shared with every workspace using '--cache shared'; they are readable and writable by all of them."
            )
        }

        return lines
    }

    private static func sessionDescription(shell: Bool, command: [String]) -> String {
        if shell {
            return "shell (/bin/bash)"
        }

        if !command.isEmpty {
            return "command (\(summarizedCommand(command)))"
        }

        return "agent entrypoint"
    }

    private static func summarizedCommand(_ command: [String]) -> String {
        guard let executable = command.first else {
            return "<unknown>"
        }

        let argumentCount = command.count - 1
        switch argumentCount {
        case ..<1:
            return executable
        case 1:
            return "\(executable), 1 arg"
        default:
            return "\(executable), \(argumentCount) args"
        }
    }
}
