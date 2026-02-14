import Foundation

/// Builds the full mount list for a container run (workspace, git/SSH, agent state).
enum MountResolver: Sendable {
    /// Resolve all mounts for the given target directory, agent, and options.
    /// Copies git/SSH configs to the XDG state dir to work around VirtioFS uid issues.
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
        // VirtioFS preserves host file ownership/permissions, so files owned by the
        // macOS user (uid 501) with 600 permissions are unreadable by the container's
        // coder user (uid 1001). We copy to the XDG state dir where we control
        // permissions, and mount the copies. The Containerfile has symlinks from
        // the expected paths into these mount points.
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig")
            if fm.fileExists(atPath: gitconfig.path) {
                let gitDir = Paths.stateDir.appendingPathComponent("git")
                do {
                    try fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
                } catch {
                    logger.warning("Failed to create git state directory \(gitDir.path): \(error.localizedDescription)")
                }
                let dest = gitDir.appendingPathComponent(".gitconfig")
                try? fm.removeItem(at: dest)
                do {
                    try fm.copyItem(at: gitconfig, to: dest)
                } catch {
                    logger.warning("Failed to copy .gitconfig to container state: \(error.localizedDescription)")
                }
                mounts.append(
                    Mount(
                        hostPath: gitDir.path,
                        guestPath: "/home/coder/.gitconfig-dir",
                        readOnly: true
                    ))
            }

            let sshDir = home.appendingPathComponent(".ssh")
            if fm.fileExists(atPath: sshDir.path) {
                let sshCopy = Paths.stateDir.appendingPathComponent("ssh")
                // Fresh copy each run to pick up key changes.
                // Copy files individually to skip sockets (SSH agent) and other non-regular files.
                try? fm.removeItem(at: sshCopy)
                do {
                    try fm.createDirectory(at: sshCopy, withIntermediateDirectories: true)
                    let contents = try fm.contentsOfDirectory(atPath: sshDir.path)
                    for item in contents {
                        let src = sshDir.appendingPathComponent(item)
                        var isDir: ObjCBool = false
                        guard fm.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else {
                            continue
                        }
                        try fm.copyItem(at: src, to: sshCopy.appendingPathComponent(item))
                    }
                } catch {
                    logger.warning("Failed to copy .ssh files to container state: \(error.localizedDescription)")
                }
                mounts.append(
                    Mount(
                        hostPath: sshCopy.path,
                        guestPath: "/home/coder/.ssh",
                        readOnly: true
                    ))
            }
        }

        // Persistent agent credential state → /home/coder/.<agent-config-dir>
        // This lets OAuth tokens survive container restarts so users only auth once.
        let agentStateDir = Paths.stateDir.appendingPathComponent(agent)
        do {
            try FileManager.default.createDirectory(at: agentStateDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create agent state directory \(agentStateDir.path): \(error.localizedDescription)")
        }

        switch agent {
        case "claude-code":
            // Mount a single directory for all Claude Code state.
            // Claude Code uses ~/.claude/ for config/plugins and ~/.claude.json for account state.
            // We can't mount .claude.json as a single file because VirtioFS doesn't support
            // atomic rename on bind-mounted files (EBUSY). Instead, we mount a directory at
            // ~/.claude-state/ and the Containerfile symlinks ~/.claude.json into it.
            let claudeDir = agentStateDir.appendingPathComponent("claude")
            do {
                try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            } catch {
                logger.warning(
                    "Failed to create Claude config directory \(claudeDir.path): \(error.localizedDescription)")
            }
            mounts.append(
                Mount(
                    hostPath: claudeDir.path,
                    guestPath: "/home/coder/.claude",
                    readOnly: false
                ))
            let claudeStateDir = agentStateDir.appendingPathComponent("claude-state")
            do {
                try FileManager.default.createDirectory(at: claudeStateDir, withIntermediateDirectories: true)
            } catch {
                logger.warning(
                    "Failed to create Claude state directory \(claudeStateDir.path): \(error.localizedDescription)"
                )
            }
            mounts.append(
                Mount(
                    hostPath: claudeStateDir.path,
                    guestPath: "/home/coder/.claude-state",
                    readOnly: false
                ))
        case "codex":
            let codexDir = agentStateDir.appendingPathComponent("codex")
            do {
                try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
            } catch {
                logger.warning(
                    "Failed to create Codex state directory \(codexDir.path): \(error.localizedDescription)")
            }
            mounts.append(
                Mount(
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
