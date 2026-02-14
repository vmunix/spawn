import Foundation

/// Seeds Claude Code's settings.json with safe-mode permission rules.
/// Reads the existing file, checks for a `permissions` key, and merges
/// seed rules only if permissions haven't been customized.
enum SettingsSeeder: Sendable {
    /// The default allow rules for safe mode — local git, build tools, file operations.
    static let seedAllow: [String] = [
        "Bash(git add:*)",
        "Bash(git commit:*)",
        "Bash(git diff:*)",
        "Bash(git status:*)",
        "Bash(git log:*)",
        "Bash(git branch:*)",
        "Bash(git checkout:*)",
        "Bash(git switch:*)",
        "Bash(git stash:*)",
        "Bash(git rebase:*)",
        "Bash(git reset:*)",
        "Bash(git restore:*)",
        "Bash(git show:*)",
        "Bash(git tag:*)",
        "Bash(git fetch:*)",
        "Bash(git pull:*)",
        "Bash(git merge:*)",
        "Bash(make:*)",
        "Bash(swift:*)",
        "Bash(cargo:*)",
        "Bash(go:*)",
        "Bash(cmake:*)",
        "Bash(ninja:*)",
        "Bash(npm:*)",
        "Bash(node:*)",
        "Bash(python:*)",
        "Bash(pip:*)",
    ]

    /// The default deny rules for safe mode — remote-write git/gh operations.
    static let seedDeny: [String] = [
        "Bash(git push:*)",
        "Bash(git remote add:*)",
        "Bash(git remote set-url:*)",
        "Bash(gh pr create:*)",
        "Bash(gh pr merge:*)",
        "Bash(gh pr close:*)",
        "Bash(gh issue create:*)",
        "Bash(gh issue close:*)",
        "Bash(gh release:*)",
        "Bash(gh repo:*)",
    ]

    /// Seed safe-mode permissions into the Claude Code settings directory.
    /// - Parameter settingsDir: The directory containing `settings.json` (e.g. `~/.claude/` inside the container,
    ///   which maps to `~/.local/state/spawn/claude-code/claude/` on the host).
    static func seed(settingsDir: URL) {
        let settingsFile = settingsDir.appendingPathComponent("settings.json")
        let fm = FileManager.default

        // Read existing settings if present
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsFile.path) {
            guard let data = try? Data(contentsOf: settingsFile),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                logger.warning("Malformed settings.json at \(settingsFile.path), skipping seed")
                return
            }
            settings = json
        }

        // If permissions key already exists (even empty), user has customized — leave it alone
        if settings["permissions"] != nil {
            return
        }

        // Merge seed permissions
        settings["permissions"] = [
            "allow": seedAllow,
            "deny": seedDeny,
        ]

        // Write back
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys]
            )
        else {
            logger.warning("Failed to serialize settings.json")
            return
        }

        do {
            try fm.createDirectory(at: settingsDir, withIntermediateDirectories: true)
            try data.write(to: settingsFile)
        } catch {
            logger.warning("Failed to write settings.json: \(error.localizedDescription)")
        }
    }
}
