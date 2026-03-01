import Foundation

/// Builds the full mount list for a container run (workspace, git/SSH, agent state).
enum MountResolver: Sendable {
    /// Ensure a directory exists, logging a warning on failure.
    private static func ensureDirectory(_ dir: URL, label: String, using fm: FileManager) {
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create \(label) directory \(dir.path): \(error.localizedDescription)")
        }
    }

    /// Resolve all mounts for the given target directory, agent, and options.
    /// Copies git/SSH configs to the XDG state dir to work around VirtioFS uid issues.
    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool,
        agent: String
    ) -> [Mount] {
        let fm = FileManager.default
        let stateDir = Paths.stateDir
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
            let home = fm.homeDirectoryForCurrentUser

            let gitconfig = home.appendingPathComponent(".gitconfig")
            if fm.fileExists(atPath: gitconfig.path) {
                let gitDir = stateDir.appendingPathComponent("git")
                ensureDirectory(gitDir, label: "git state", using: fm)
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
                let sshCopy = stateDir.appendingPathComponent("ssh")
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
                        // Skip symlinks to prevent exfiltrating files outside ~/.ssh
                        let attrs = try? fm.attributesOfItem(atPath: src.path)
                        if let fileType = attrs?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                            continue
                        }
                        try fm.copyItem(at: src, to: sshCopy.appendingPathComponent(item))
                        // Set restrictive permissions on private key files
                        if !item.hasSuffix(".pub") && item != "known_hosts"
                            && item != "known_hosts.old" && item != "config"
                        {
                            try? fm.setAttributes(
                                [.posixPermissions: 0o600],
                                ofItemAtPath: sshCopy.appendingPathComponent(item).path
                            )
                        }
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

            // GitHub CLI auth config (~/.config/gh/) — only copy auth and config files
            let ghDir = home.appendingPathComponent(".config/gh")
            if fm.fileExists(atPath: ghDir.path) {
                let ghCopy = stateDir.appendingPathComponent("gh")
                try? fm.removeItem(at: ghCopy)
                do {
                    try fm.createDirectory(at: ghCopy, withIntermediateDirectories: true)
                    for file in ["hosts.yml", "config.yml"] {
                        let src = ghDir.appendingPathComponent(file)
                        if fm.fileExists(atPath: src.path) {
                            try fm.copyItem(at: src, to: ghCopy.appendingPathComponent(file))
                        }
                    }
                } catch {
                    logger.warning("Failed to copy gh config to container state: \(error.localizedDescription)")
                }
                mounts.append(
                    Mount(
                        hostPath: ghCopy.path,
                        guestPath: "/home/coder/.config/gh",
                        readOnly: true
                    ))
            }
        }

        // Persistent agent credential state → /home/coder/.<agent-config-dir>
        // This lets OAuth tokens survive container restarts so users only auth once.
        let agentStateDir = stateDir.appendingPathComponent(agent)
        ensureDirectory(agentStateDir, label: "agent state", using: fm)

        switch agent {
        case "claude-code":
            // Mount a single directory for all Claude Code state.
            // Claude Code uses ~/.claude/ for config/plugins and ~/.claude.json for account state.
            // We can't mount .claude.json as a single file because VirtioFS doesn't support
            // atomic rename on bind-mounted files (EBUSY). Instead, we mount a directory at
            // ~/.claude-state/ and the Containerfile symlinks ~/.claude.json into it.
            let claudeDir = agentStateDir.appendingPathComponent("claude")
            ensureDirectory(claudeDir, label: "Claude config", using: fm)
            mounts.append(
                Mount(
                    hostPath: claudeDir.path,
                    guestPath: "/home/coder/.claude",
                    readOnly: false
                ))
            let claudeStateDir = agentStateDir.appendingPathComponent("claude-state")
            ensureDirectory(claudeStateDir, label: "Claude state", using: fm)
            mounts.append(
                Mount(
                    hostPath: claudeStateDir.path,
                    guestPath: "/home/coder/.claude-state",
                    readOnly: false
                ))
        case "codex":
            let codexDir = agentStateDir.appendingPathComponent("codex")
            ensureDirectory(codexDir, label: "Codex state", using: fm)
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
