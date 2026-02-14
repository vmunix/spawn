---
title: Authentication
nav_order: 6
---

# Authentication

spawn supports multiple authentication methods for AI agents and GitHub CLI access.

## OAuth (recommended)

On first run, Claude Code and Codex will prompt you to authenticate via OAuth in your browser. This is the easiest method and requires no API keys.

spawn persists OAuth credentials in `~/.local/state/spawn/<agent>/` on the host and mounts them into each container, so you only need to authenticate once. Credentials survive container restarts.

## GitHub CLI

To authenticate `gh` inside a container, drop into a shell and run the login flow:

```bash
spawn . --shell
# Inside the container:
gh auth login
```

spawn copies your host `~/.config/gh/` directory into the container on each run, so if you've already authenticated `gh` on your Mac, it should work automatically.

## API keys

Pass API keys as environment variables:

```bash
# Inline
spawn . --env ANTHROPIC_API_KEY=sk-ant-...
spawn . --env GH_TOKEN=ghp_...

# Multiple variables
spawn . --env ANTHROPIC_API_KEY=sk-ant-... --env GH_TOKEN=ghp_...

# From an env file
spawn . --env-file ~/.config/spawn/env
```

### Default env file

spawn automatically loads `~/.config/spawn/env` if it exists. This file uses `KEY=VALUE` format:

```bash
# ~/.config/spawn/env
ANTHROPIC_API_KEY=sk-ant-...
GH_TOKEN=ghp_...
```

Comments (lines starting with `#`) and blank lines are ignored. Values can optionally be quoted:

```bash
ANTHROPIC_API_KEY="sk-ant-..."
```

CLI `--env` flags override values from the env file.

## Credential persistence

| Agent | Host path | Container path |
|-------|-----------|----------------|
| Claude Code | `~/.local/state/spawn/claude-code/claude/` | `/home/coder/.claude/` |
| Claude Code | `~/.local/state/spawn/claude-code/claude-state/` | `/home/coder/.claude-state/` |
| Codex | `~/.local/state/spawn/codex/codex/` | `/home/coder/.codex/` |
| Git config | `~/.local/state/spawn/git/` | `/home/coder/.gitconfig-dir/` |
| SSH keys | `~/.local/state/spawn/ssh/` | `/home/coder/.ssh/` |
| gh CLI | `~/.local/state/spawn/gh/` | `/home/coder/.config/gh/` |

These directories are mounted into every container run. Git config and SSH keys are mounted read-only; agent credentials are read-write.
