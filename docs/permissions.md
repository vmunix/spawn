---
title: Permissions
nav_order: 5
---

# Permissions

spawn has two permission modes: **safe mode** (default) and **yolo mode**. Safe mode gates remote-write git/gh operations behind interactive approval prompts. Yolo mode runs fully unrestricted.

## Safe mode (default)

In safe mode, agents can perform all local operations freely -- file edits, builds, tests, local git operations, and remote reads. Remote-write operations require you to approve them interactively.

### What's gated (requires approval)

- `git push`
- `git remote add`, `git remote set-url`
- `gh pr create`, `gh pr merge`, `gh pr close`
- `gh issue create`, `gh issue close`
- `gh release`
- `gh repo`

### What's allowed (no prompt)

- All local file operations
- All build and test commands
- Local git: `add`, `commit`, `diff`, `status`, `log`, `branch`, `checkout`, `switch`, `stash`, `rebase`, `reset`, `restore`, `show`, `tag`, `merge`
- Remote reads: `git fetch`, `git pull`, `gh pr view`, `gh issue list`

## Yolo mode

```bash
spawn . --yolo
```

All operations run without prompts. The container is still the sandbox boundary -- the agent can't access anything outside the mounted directories.

## How it works

### Claude Code

In safe mode, spawn runs Claude Code **without** `--dangerously-skip-permissions` and seeds a `settings.json` with allow/deny rules:

- **Allow rules** cover local git commands, build tools (make, swift, cargo, go, cmake, ninja, npm, node, python, pip), and remote reads
- **Deny rules** cover the remote-write operations listed above

Claude Code's native permission system enforces these rules. When Claude Code encounters a denied operation, it prompts you for approval.

Additionally, git/gh wrapper scripts intercept the actual binaries and prompt on TTY before executing remote-write commands. This provides defense in depth.

In yolo mode, spawn runs Claude Code with `--dangerously-skip-permissions` and the wrapper scripts are inactive.

### Codex

Codex always runs with `--full-auto` (its architecture requires it). In safe mode, the git/gh wrapper scripts provide the permission gates. In yolo mode, the wrapper scripts are inactive and Codex runs fully unrestricted.

## Customizing permissions

### Claude Code settings

The seeded `settings.json` lives at:

```
~/.local/state/spawn/claude-code/claude/settings.json
```

Edit this file on the host to change the default allow/deny rules for all projects. spawn only seeds permissions if the file doesn't already contain a `permissions` key -- once you've customized it, spawn leaves it alone.

Claude Code also supports per-project settings via `.claude/settings.json` in the workspace directory. These accumulate naturally as you use Claude Code and approve or deny operations.

### Opting out of seeded permissions

Set an empty permissions object in `settings.json` to prevent spawn from re-seeding:

```json
{
  "permissions": {}
}
```

## Known limitations

- Wrapper scripts can be bypassed by calling the binary directly (e.g., `/usr/bin/git push` or `command git push`). This is a known limitation -- spawn's permission system is not a security boundary.
- When stdin is not a TTY (piped input), the wrapper scripts block the operation and print an error rather than prompting.
- The `SPAWN_SAFE_MODE` environment variable is visible inside the container. An agent could theoretically unset it to bypass the wrappers.
