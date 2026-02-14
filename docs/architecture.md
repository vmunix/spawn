---
title: Architecture
nav_order: 7
---

# Architecture

## Directory layout

spawn follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) for all configuration and state.

| Path | Purpose |
|------|---------|
| `~/.config/spawn/env` | Default environment variables |
| `~/.local/state/spawn/<agent>/` | Agent credentials and session state |
| `~/.local/state/spawn/git/` | Copied git config for container mounts |
| `~/.local/state/spawn/ssh/` | Copied SSH keys for container mounts |
| `~/.local/state/spawn/gh/` | Copied gh CLI config for container mounts |

These paths respect `XDG_CONFIG_HOME` and `XDG_STATE_HOME` environment variables. For example, if `XDG_STATE_HOME` is set to `/custom/state`, spawn stores state at `/custom/state/spawn/` instead of `~/.local/state/spawn/`.

## Container images

spawn uses layered container images. All toolchain images extend `spawn-base:latest`:

```
spawn-base:latest
  ├── spawn-cpp:latest
  ├── spawn-rust:latest
  └── spawn-go:latest
```

### Base image contents

The base image (`spawn-base:latest`) includes:
- Ubuntu 24.04
- Node.js, npm, Python 3
- Claude Code (native installer), Codex (npm)
- git, gh CLI, curl, wget
- ripgrep, fd-find, jq, tree
- Safe-mode wrapper scripts for git/gh
- Non-root `coder` user with sudo access

### Image management

```bash
spawn build              # Build all images
spawn build base         # Build base only
spawn build rust         # Build a toolchain image
spawn image list         # List spawn images
spawn image rm <name>    # Remove a spawn image
```

Containerfile content is embedded in the `spawn` binary as string literals, so `spawn build` works after installation without depending on the source repository.

## Run pipeline

When you run `spawn .`, the following modules execute in sequence:

```
RunCommand.run()
  → AgentProfile.named()          # Validate agent (claude-code/codex)
  → ToolchainDetector.detect()    # Auto-detect or use override
  → ImageResolver.resolve()       # Map toolchain to image name
  → MountResolver.resolve()       # Build mount list
  → EnvLoader.load/loadDefault()  # Load env vars
  → ContainerRunner.run()         # Launch container
```

## Design decisions

### Apple's container CLI

All container interaction goes through Apple's [`container`](https://github.com/apple/containerization) CLI, auto-detected at `/opt/homebrew/bin/container` or `/usr/local/bin/container`, falling back to PATH lookup. Override with the `CONTAINER_PATH` environment variable.

### TTY via execv

When stdin is a real terminal, spawn uses `execv` to replace its process with `container`, giving the container CLI direct TTY access. This is required for interactive I/O. When stdin is a pipe, it falls back to `Foundation.Process` with signal forwarding.

### VirtioFS workaround

VirtioFS preserves host file ownership and permissions. Files owned by the macOS user (uid 501) with 600 permissions are unreadable by the container's `coder` user (uid 1001). spawn copies git config and SSH keys to the state directory where it controls permissions, then mounts the copies.

Single-file bind mounts also don't support atomic rename (EBUSY). `~/.claude.json` is handled via a symlink into a directory mount (`~/.claude-state/`) to work around this.

### Credential persistence

Agent credentials are stored on the host at `~/.local/state/spawn/<agent>/` and mounted into containers. This means users authenticate once and credentials survive container restarts. No API keys are required for Claude Pro/Max plan users who authenticate via OAuth.

### SSH key handling

SSH keys are copied (not mounted directly) to the state directory. Symlinks are filtered out to prevent exfiltrating files outside `~/.ssh/`. Private keys get `0600` permissions on the copies.
