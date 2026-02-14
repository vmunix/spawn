import Foundation

enum MountResolver {
    /// Directory on the host that persists agent credentials across container runs.
    static let stateDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ccc")
            .appendingPathComponent("state")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool,
        agent: String
    ) -> [Mount] {
        var mounts: [Mount] = []

        // Primary target
        mounts.append(Mount(hostPath: target.path, readOnly: false))

        // Additional read-write mounts
        for path in additional {
            mounts.append(Mount(hostPath: path, readOnly: false))
        }

        // Read-only mounts
        for path in readOnly {
            mounts.append(Mount(hostPath: path, readOnly: true))
        }

        // Git/SSH mounts
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig").path
            if fm.fileExists(atPath: gitconfig) {
                mounts.append(Mount(
                    hostPath: gitconfig,
                    guestPath: "/home/coder/.gitconfig",
                    readOnly: true
                ))
            }

            let sshDir = home.appendingPathComponent(".ssh").path
            if fm.fileExists(atPath: sshDir) {
                mounts.append(Mount(
                    hostPath: sshDir,
                    guestPath: "/home/coder/.ssh",
                    readOnly: true
                ))
            }
        }

        // Persistent agent credential state (~/.ccc/state/<agent>/ → /home/coder/.<agent-config-dir>)
        // This lets OAuth tokens survive container restarts so users only auth once.
        let agentStateDir = stateDir.appendingPathComponent(agent)
        try? FileManager.default.createDirectory(at: agentStateDir, withIntermediateDirectories: true)

        switch agent {
        case "claude-code":
            // Mount a single directory for all Claude Code state.
            // Claude Code uses ~/.claude/ for config/plugins and ~/.claude.json for account state.
            // We can't mount .claude.json as a single file because VirtioFS doesn't support
            // atomic rename on bind-mounted files (EBUSY). Instead, we mount a directory at
            // ~/.claude-state/ and the Containerfile symlinks ~/.claude.json into it.
            let claudeDir = agentStateDir.appendingPathComponent("claude")
            try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: claudeDir.path,
                guestPath: "/home/coder/.claude",
                readOnly: false
            ))
            let claudeStateDir = agentStateDir.appendingPathComponent("claude-state")
            try? FileManager.default.createDirectory(at: claudeStateDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: claudeStateDir.path,
                guestPath: "/home/coder/.claude-state",
                readOnly: false
            ))
        case "codex":
            let codexDir = agentStateDir.appendingPathComponent("codex")
            try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: codexDir.path,
                guestPath: "/home/coder/.codex",
                readOnly: false
            ))
        default:
            break
        }

        return mounts
    }
}
