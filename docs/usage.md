---
title: Usage
nav_order: 3
---

# Usage

## Subcommands

| Command | Description |
|---------|-------------|
| `spawn run` (default) | Run an AI coding agent in a sandboxed container |
| `spawn build` | Build or pull container images |
| `spawn image list` | List available spawn images |
| `spawn image rm` | Remove one or more spawn images |
| `spawn list` | List running containers |
| `spawn stop` | Stop a running container |
| `spawn exec` | Execute a command in a running container |

`run` is the default subcommand, so `spawn .` is equivalent to `spawn run .`.

## spawn run

```
USAGE: spawn run <path> [<agent>] [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `path` | Directory to mount as workspace |
| `agent` | `claude-code` (default) or `codex` |

### Options

| Option | Description |
|--------|-------------|
| `--mount <dir>` | Additional directory to mount (repeatable) |
| `--read-only <dir>` | Mount directory read-only (repeatable) |
| `--env <KEY=VALUE>` | Environment variable (repeatable) |
| `--env-file <path>` | Path to env file |
| `--image <name>` | Override base image |
| `--toolchain <name>` | Override toolchain: `base`, `cpp`, `rust`, `go` |
| `--cpus <n>` | CPU cores (default: 4) |
| `--memory <size>` | Memory (default: 8g) |
| `--shell` | Drop into shell instead of running agent |
| `--no-git` | Don't mount ~/.gitconfig or SSH keys |
| `--verbose` | Show container commands |
| `--yolo` | Full auto mode -- skip all permission gates |

### Examples

```bash
# Run Claude Code with auto-detected toolchain
spawn .

# Run Codex instead
spawn . codex

# Mount additional directories
spawn . --mount ~/shared-libs --mount ~/data

# Mount a directory read-only
spawn . --read-only ~/reference-docs

# Pass environment variables
spawn . --env ANTHROPIC_API_KEY=sk-ant-...

# Use an env file
spawn . --env-file ~/.config/spawn/env

# Override the toolchain
spawn . --toolchain rust

# Override the container image entirely
spawn . --image my-custom-image:latest

# Allocate more resources
spawn . --cpus 8 --memory 16g

# Full auto mode (no permission prompts)
spawn . --yolo

# Debug: drop into a shell
spawn . --shell

# See what container command spawn is running
spawn . --verbose
```

## spawn build

```bash
spawn build base       # Build the base image
spawn build rust       # Build the Rust toolchain image
spawn build cpp        # Build the C++ toolchain image
spawn build go         # Build the Go toolchain image
spawn build            # Build all images (base first)
```

Toolchain images extend `spawn-base:latest`, so the base image must be built first. Running `spawn build` without arguments builds all images in the correct order.

## spawn image

```bash
spawn image list       # List spawn-* images (default)
spawn image list --all # List all images including non-spawn ones
spawn image rm spawn-rust:latest spawn-go:latest  # Remove images
```

`spawn image rm` only removes `spawn-*` images and refuses to remove `spawn-base` (since other images depend on it).

## spawn list / stop / exec

```bash
spawn list              # List running containers
spawn stop <id>         # Stop a running container
spawn exec <id> -- ls   # Run a command in a running container
```
