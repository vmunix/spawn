# Permission Modes and Documentation Site Design

**Date:** 2026-02-14
**Status:** Approved

## Problem

spawn currently runs agents in full-auto mode (`--dangerously-skip-permissions` for Claude Code, `--full-auto` for Codex). Users want the agent to run unrestricted locally (file edits, builds, tests, local git) but require confirmation before remote-write operations (git push, PR create/merge, etc.).

Additionally, the README is growing beyond what a landing page should contain. Detailed documentation needs a proper home.

## Requirements

- Safe mode is the default; users opt into full auto with `--yolo`
- Gate remote-write git/gh operations: `git push`, `gh pr create`, `gh pr merge`, `gh pr close`, `gh issue create`, `gh issue close`, `gh release`, `gh repo`
- Allow remote-read operations: `git fetch`, `git pull`, `gh pr view`, `gh issue list`
- Gating mechanism: interactive TTY prompt ("allow? [y/N]")
- Use agent-native permissions where available, wrapper scripts as fallback
- Seed sensible defaults for Claude Code's permission system, persist per-repo customizations naturally
- Build a GitHub Pages docs site for detailed documentation

## Design

### CLI Interface

New flag on `spawn run`:

```
--yolo    Full auto mode — skip all permission gates
```

Safe mode is the default (no flag needed). In `RunCommand.swift`:

```swift
@Flag(name: .long, help: "Full auto mode — skip all permission gates.")
var yolo: Bool = false
```

`AgentProfile` splits the entrypoint:

```swift
struct AgentProfile {
    let name: String
    let safeEntrypoint: [String]    // e.g. ["claude"]
    let yoloEntrypoint: [String]    // e.g. ["claude", "--dangerously-skip-permissions"]
    let requiredEnvVars: [String]
    let defaultCPUs: Int
    let defaultMemory: String
}
```

Entrypoint selection:

```swift
let entrypoint = shell ? ["/bin/bash"] : (yolo ? profile.yoloEntrypoint : profile.safeEntrypoint)
```

### Claude Code Safe Mode — Settings Seed

When running Claude Code in safe mode, spawn seeds `~/.claude/settings.json` in the state directory (`~/.local/state/spawn/claude-code/claude/settings.json`) if it doesn't already contain permission rules.

Seed content:

```json
{
  "permissions": {
    "allow": [
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
      "Bash(pip:*)"
    ],
    "deny": [
      "Bash(git push:*)",
      "Bash(git remote add:*)",
      "Bash(git remote set-url:*)",
      "Bash(gh pr create:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh pr close:*)",
      "Bash(gh issue create:*)",
      "Bash(gh issue close:*)",
      "Bash(gh release:*)",
      "Bash(gh repo:*)"
    ]
  }
}
```

Seeding logic:
- On safe-mode launch, read existing `settings.json` from the state dir
- If it already has a `permissions` key, leave it alone (user has customized)
- If it doesn't, merge in the seed permissions
- If JSON is malformed, log a warning and skip (don't crash)
- One-time operation — once seeded, user and Claude Code modify freely

Claude Code's two-tier settings system handles per-repo customization naturally:
- User-level (`~/.claude/settings.json` in container) — universal seed, shared across repos
- Project-level (`.claude/settings.json` in workspace) — per-repo, accumulates during use

### Codex Safe Mode — Git/GH Wrapper Scripts

Wrapper scripts installed in the container image intercept remote-write operations.

Two scripts embedded in `ContainerfileTemplates.swift`:

`/usr/local/lib/spawn/git-guard.sh` — intercepts `git push`, `git remote add`, `git remote set-url`. Skips option flags (`-c`, `--config`, `-C`) to find the actual subcommand. Prompts on TTY.

`/usr/local/lib/spawn/gh-guard.sh` — intercepts `gh pr create/merge/close`, `gh issue create/close`, `gh release`, `gh repo`. Prompts on TTY.

Activation via env var: wrappers always installed but only active when `SPAWN_SAFE_MODE=1` is set. Pass through immediately when unset.

Symlinks in the image put wrappers ahead of real binaries in PATH:
```
/usr/local/bin/git → /usr/local/lib/spawn/git-guard.sh
/usr/local/bin/gh  → /usr/local/lib/spawn/gh-guard.sh
```

### RunCommand Orchestration

| Step | Safe mode | Yolo mode |
|------|-----------|-----------|
| Entrypoint | `profile.safeEntrypoint` | `profile.yoloEntrypoint` |
| Settings seed | Yes (Claude Code only) | No |
| `SPAWN_SAFE_MODE` env | `"1"` | unset |
| Mounts | Unchanged | Unchanged |

Per-agent summary:

| | Claude Code safe | Claude Code yolo | Codex safe | Codex yolo |
|---|---|---|---|---|
| Entrypoint | `claude` | `claude --dangerously-skip-permissions` | `codex --full-auto` | `codex --full-auto` |
| Settings seed | Yes | No | No | No |
| `SPAWN_SAFE_MODE` | `1` | unset | `1` | unset |
| Remote git gating | Claude Code deny rules + wrapper | None | Wrapper only | None |

### Error Handling and Edge Cases

**Settings file conflicts:**
- Missing `permissions` key → seeder re-applies. User can set `"permissions": {}` to opt out.
- Malformed JSON → log warning, skip seeding, agent launches without pre-approved rules.

**Wrapper script edge cases:**
- Git flags before subcommand (`git -c ... push`) → wrapper iterates past option flags to find subcommand.
- Direct binary path (`/usr/bin/git push`) or `command git push` → bypasses wrapper. Known limitation for v1.
- No TTY (piped input) → wrapper blocks and prints error: `"spawn: git push blocked — safe mode requires a TTY for approval"`.

**Mode visibility:**
- Safe mode prints: `"Safe mode: remote git operations require approval (use --yolo to disable)"`
- Yolo mode prints: `"Yolo mode: all operations unrestricted"`

**`--yolo` + `--shell`:**
- Shell mode bypasses agent entrypoint but `SPAWN_SAFE_MODE` still applies. Wrapper scripts active in shell unless `--yolo` passed.

### New and Modified Files

| File | Change |
|---|---|
| `Sources/Types.swift` | Split `entrypoint` into `safeEntrypoint` / `yoloEntrypoint` |
| `Sources/RunCommand.swift` | Add `--yolo` flag, entrypoint selection, settings seed call, env injection |
| `Sources/SettingsSeeder.swift` | **New.** Read/merge seed permissions into Claude Code's settings.json |
| `Sources/ContainerfileTemplates.swift` | Add wrapper scripts and symlinks to base image template |
| `Tests/TypesTests.swift` | Update for new entrypoint fields |
| `Tests/SettingsSeederTests.swift` | **New.** Test merge logic |
| `Tests/ContainerRunnerTests.swift` | Test `SPAWN_SAFE_MODE` env var in buildArgs |
| `CLAUDE.md` | Document `--yolo`, safe mode design, `SettingsSeeder` module |
| `README.md` | Slim down, add `--yolo` to options, link to docs site |

### Documentation Site (GitHub Pages + Jekyll)

Structure:

```
docs/
  index.md              # Home — what it does, install, quick start
  getting-started.md    # Full install guide, first run, building images
  usage.md              # All spawn run options, subcommands, examples
  toolchains.md         # Detection logic, supported toolchains, overrides
  permissions.md        # Safe mode vs yolo, what's gated, customization
  authentication.md     # OAuth, gh auth, API keys, credential persistence
  architecture.md       # Directory layout, container images, design decisions
  _config.yml           # Jekyll config: theme, title, nav
```

Jekyll with GitHub Pages — markdown in `docs/`, served from `docs/` folder on `main`, no build step needed.

README slimmed to: one-liner, what it does (condensed), requirements, install, quick start, link to docs, dev section, license.

Sections moving to docs: detailed usage/options, toolchain detection, authentication, directory layout, container images, permission modes.

CLAUDE.md unchanged — it's for the AI agent, not end users.

## Known Limitations (v1)

- Wrapper scripts can be bypassed via direct binary paths or raw SSH/curl. Acceptable for v1 — covers the 99% path.
- Codex lacks granular permission control; wrapper is best-effort.
- `SPAWN_SAFE_MODE` env var is visible to the agent and could theoretically be unset. Not a security boundary.
